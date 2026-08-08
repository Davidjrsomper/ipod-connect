import Foundation

struct FLACInfo {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var date: String?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: Double = 0
    var sampleRate: Int = 0
    var bitsPerSample: Int = 0
}

/// Minimal native parser for the FLAC container: STREAMINFO (type 0),
/// VORBIS_COMMENT (type 4) and PICTURE (type 6) metadata blocks.
enum FLACParser {

    static func parse(url: URL) -> FLACInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var info = FLACInfo()
        var isLast = false
        while !isLast {
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
            let bytes = [UInt8](header)
            isLast = bytes[0] & 0x80 != 0
            let type = bytes[0] & 0x7F
            let length = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            guard length >= 0 else { break }

            if type == 0 || type == 4 {
                guard let block = try? handle.read(upToCount: length), block.count == length else { break }
                if type == 0 { parseStreamInfo([UInt8](block), into: &info) }
                else { parseVorbisComments([UInt8](block), into: &info) }
            } else {
                guard skip(handle: handle, by: length) else { break }
            }
        }
        return info
    }

    /// Returns embedded cover art data from the PICTURE block, if present.
    static func artwork(url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var isLast = false
        while !isLast {
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
            let bytes = [UInt8](header)
            isLast = bytes[0] & 0x80 != 0
            let type = bytes[0] & 0x7F
            let length = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])

            if type == 6 {
                guard let block = try? handle.read(upToCount: length), block.count == length else { break }
                return pictureData([UInt8](block))
            } else {
                guard skip(handle: handle, by: length) else { break }
            }
        }
        return nil
    }

    private static func skip(handle: FileHandle, by length: Int) -> Bool {
        guard let offset = try? handle.offset() else { return false }
        do { try handle.seek(toOffset: offset + UInt64(length)); return true } catch { return false }
    }

    private static func parseStreamInfo(_ b: [UInt8], into info: inout FLACInfo) {
        guard b.count >= 18 else { return }
        let sampleRate = Int(b[10]) << 12 | Int(b[11]) << 4 | Int(b[12]) >> 4
        let bps = (Int(b[12] & 0x01) << 4 | Int(b[13]) >> 4) + 1
        let totalSamples = UInt64(b[13] & 0x0F) << 32 | UInt64(b[14]) << 24
            | UInt64(b[15]) << 16 | UInt64(b[16]) << 8 | UInt64(b[17])
        info.sampleRate = sampleRate
        info.bitsPerSample = bps
        if sampleRate > 0 { info.duration = Double(totalSamples) / Double(sampleRate) }
    }

    private static func parseVorbisComments(_ b: [UInt8], into info: inout FLACInfo) {
        var o = 0
        func readU32LE() -> Int? {
            guard o + 4 <= b.count else { return nil }
            let v = Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
            o += 4
            return v
        }
        guard let vendorLen = readU32LE(), vendorLen >= 0, o + vendorLen <= b.count else { return }
        o += vendorLen
        guard let count = readU32LE(), count >= 0 else { return }

        for _ in 0..<min(count, 10_000) {
            guard let len = readU32LE(), len >= 0, o + len <= b.count else { return }
            let comment = String(bytes: b[o..<o + len], encoding: .utf8) ?? ""
            o += len
            guard let eq = comment.firstIndex(of: "=") else { continue }
            let key = comment[..<eq].uppercased()
            let value = String(comment[comment.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            switch key {
            case "TITLE": info.title = value
            case "ARTIST": info.artist = info.artist.map { "\($0), \(value)" } ?? value
            case "ALBUM": info.album = value
            case "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST": info.albumArtist = value
            case "GENRE": info.genre = value
            case "DATE", "YEAR": info.date = value
            case "TRACKNUMBER": info.trackNumber = leadingInt(value)
            case "DISCNUMBER": info.discNumber = leadingInt(value)
            default: break
            }
        }
    }

    private static func leadingInt(_ s: String) -> Int? {
        Int(s.split(separator: "/").first.map(String.init) ?? s)
    }

    private static func pictureData(_ b: [UInt8]) -> Data? {
        var o = 0
        func readU32BE() -> Int? {
            guard o + 4 <= b.count else { return nil }
            let v = Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
            o += 4
            return v
        }
        guard readU32BE() != nil else { return nil }                       // picture type
        guard let mimeLen = readU32BE(), o + mimeLen <= b.count else { return nil }
        o += mimeLen
        guard let descLen = readU32BE(), o + descLen <= b.count else { return nil }
        o += descLen
        for _ in 0..<4 { guard readU32BE() != nil else { return nil } }    // w, h, depth, colors
        guard let dataLen = readU32BE(), dataLen > 0, o + dataLen <= b.count else { return nil }
        return Data(b[o..<o + dataLen])
    }
}
