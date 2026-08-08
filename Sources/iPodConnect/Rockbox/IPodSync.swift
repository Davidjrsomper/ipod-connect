import Foundation

/// A music file living on the iPod.
struct DeviceTrack: Identifiable, Hashable {
    let id: String          // full path on the device
    let path: String
    let name: String
    let artist: String      // from the folder layout
    let album: String
    let sizeBytes: Int64

    var url: URL { URL(fileURLWithPath: path) }
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Copies music to and from a Rockboxed iPod.
///
/// Rockbox reads plain files off the disk and builds its own database, so
/// syncing is ordinary file management — no iTunesDB to write. That is why
/// this only supports Rockboxed devices: on stock Apple firmware, files
/// copied this way would be invisible to the iPod's own library.
enum IPodSync {

    /// Where music is written on the device. Rockbox scans the whole disk,
    /// but a tidy Artist/Album tree keeps its browser usable.
    static let musicRoot = "Music"

    // MARK: Reading the device

    static func tracks(onVolume mount: String) -> [DeviceTrack] {
        let root = mount + "/" + musicRoot
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [DeviceTrack] = []
        while let url = enumerator.nextObject() as? URL {
            guard Library.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            // .../Music/<Artist>/<Album>/<file>
            let album = url.deletingLastPathComponent().lastPathComponent
            let artist = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            found.append(DeviceTrack(
                id: url.path,
                path: url.path,
                name: url.deletingPathExtension().lastPathComponent,
                artist: artist == musicRoot ? "" : artist,
                album: album == musicRoot ? "" : album,
                sizeBytes: size
            ))
        }
        return found.sorted {
            if $0.artist != $1.artist { return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
            if $0.album != $1.album { return $0.album.localizedStandardCompare($1.album) == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    struct Capacity {
        let totalBytes: Int64
        let freeBytes: Int64
        var usedBytes: Int64 { totalBytes - freeBytes }
        var usedFraction: Double {
            totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        }
        var freeText: String { ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file) }
        var totalText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    }

    /// Reads free space via `statfs`.
    ///
    /// Deliberately *not* `volumeAvailableCapacityForImportantUsage`: that key
    /// is designed around APFS purgeable space and reports zero on FAT32 —
    /// which is exactly what iPods are formatted as. Trusting it would make
    /// every copy look like it had no room. `statfs` matches `df` on both.
    static func capacity(ofVolume mount: String) -> Capacity? {
        var stats = statfs()
        guard statfs(mount, &stats) == 0 else { return nil }
        let blockSize = Int64(stats.f_bsize)
        let total = Int64(stats.f_blocks) * blockSize
        let free = Int64(stats.f_bavail) * blockSize
        guard total > 0 else { return nil }
        return Capacity(totalBytes: total, freeBytes: free)
    }

    // MARK: Writing

    /// FAT32 rejects these, and a bad name fails the copy mid-sync.
    static func sanitize(_ component: String) -> String {
        let illegal = CharacterSet(charactersIn: ":/\\*?\"<>|")
        var cleaned = component.components(separatedBy: illegal).joined(separator: "_")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(".") { cleaned.removeLast() }   // FAT32 dislikes trailing dots
        if cleaned.isEmpty { cleaned = "Unknown" }
        return String(cleaned.prefix(120))
    }

    /// The path a library track will occupy on the device.
    static func destination(for track: Track, onVolume mount: String) -> URL {
        let artist = sanitize(track.sortArtist.isEmpty ? "Unknown Artist" : track.sortArtist)
        let album = sanitize(track.album.isEmpty ? "Unknown Album" : track.album)
        var name = sanitize(track.title.isEmpty ? track.url.deletingPathExtension().lastPathComponent : track.title)
        if track.trackNumber > 0 {
            name = String(format: "%02d %@", track.trackNumber, name)
        }
        return URL(fileURLWithPath: mount)
            .appendingPathComponent(musicRoot)
            .appendingPathComponent(artist)
            .appendingPathComponent(album)
            .appendingPathComponent(name)
            .appendingPathExtension(track.url.pathExtension)
    }

    static func isOnDevice(_ track: Track, mount: String) -> Bool {
        FileManager.default.fileExists(atPath: destination(for: track, onVolume: mount).path)
    }

    enum SyncOutcome {
        case copied, skippedExisting, failed(String)
    }

    /// Copies one track, creating the Artist/Album folders as needed.
    @discardableResult
    static func copy(_ track: Track, toVolume mount: String, overwrite: Bool = false) -> SyncOutcome {
        let destination = destination(for: track, onVolume: mount)
        let fm = FileManager.default

        if fm.fileExists(atPath: destination.path) {
            guard overwrite else { return .skippedExisting }
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.copyItem(at: track.url, to: destination)
            return .copied
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Deletes a track from the device and prunes folders it leaves empty.
    static func remove(_ deviceTrack: DeviceTrack, fromVolume mount: String) throws {
        let fm = FileManager.default
        try fm.removeItem(atPath: deviceTrack.path)

        // Walk up from the album folder, removing directories that are now
        // empty, but never past the Music root.
        let musicRootPath = URL(fileURLWithPath: mount)
            .appendingPathComponent(musicRoot).standardizedFileURL.path
        var directory = URL(fileURLWithPath: deviceTrack.path).deletingLastPathComponent()
        while directory.standardizedFileURL.path.hasPrefix(musicRootPath),
              directory.standardizedFileURL.path != musicRootPath {
            let contents = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            let meaningful = contents.filter { $0 != ".DS_Store" }
            guard meaningful.isEmpty else { break }
            try? fm.removeItem(at: directory)
            directory = directory.deletingLastPathComponent()
        }
    }

    /// Total size of the files a copy would add, ignoring ones already there.
    static func bytesRequired(for tracks: [Track], onVolume mount: String) -> Int64 {
        tracks.reduce(0) { total, track in
            isOnDevice(track, mount: mount) ? total : total + track.fileSize
        }
    }
}
