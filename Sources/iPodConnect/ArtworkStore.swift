import Foundation
import AppKit
import CryptoKit

/// Stores artwork the user supplies by hand for albums or individual songs
/// that have none embedded. Images are copied into Application Support and
/// keyed by album ("artist|album") or by track path — the original music
/// files are never modified.
final class ArtworkStore: @unchecked Sendable {
    static let shared = ArtworkStore()

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPod Connect", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base
    }

    static func albumKey(artist: String, album: String) -> String { "album:\(artist)|\(album)" }
    static func trackKey(path: String) -> String { "track:\(path)" }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("png")
    }

    func image(forKey key: String) -> NSImage? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    func hasImage(forKey key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    /// Reads an image the user picked, normalises it to PNG, and files it
    /// under `key`. Throws if the file isn't a readable image.
    func setImage(from sourceURL: URL, forKey key: String) throws {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw ArtworkError.unreadableImage
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ArtworkError.conversionFailed
        }
        try png.write(to: fileURL(for: key), options: .atomic)
    }

    func removeImage(forKey key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    enum ArtworkError: LocalizedError {
        case unreadableImage
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "That file couldn't be read as an image."
            case .conversionFailed: return "That image couldn't be converted."
            }
        }
    }
}
