import Foundation

/// The on-disk shape of Apple's `iTunesDB`, the database a stock iPod reads
/// its library from.
///
/// It's a tree of chunks flattened into one little-endian file. Every chunk
/// starts with a four-byte ASCII magic and a header length, so a reader can
/// skip anything it doesn't understand — which is what makes it safe to parse
/// databases written by iTunes versions we've never seen.
///
///     mhbd                     database
///      └── mhsd (type 1)       dataset: tracks
///           └── mhlt           track list
///                └── mhit      one track
///                     └── mhod string or data (title, artist, path…)
///      └── mhsd (type 2/3)     dataset: playlists
///           └── mhlp           playlist list
///                └── mhyp      one playlist
///                     └── mhip playlist entry
enum ITunesDBChunk: String {
    case database   = "mhbd"
    case dataset    = "mhsd"
    case trackList  = "mhlt"
    case track      = "mhit"
    case data       = "mhod"
    case playlists  = "mhlp"
    case playlist   = "mhyp"
    case playlistItem = "mhip"
}

/// What an `mhod` holds. Only the ones the app needs are named; the rest are
/// skipped by length, which is why unknown types cause no trouble.
enum MHODType: UInt32 {
    case title    = 1
    case location = 2     // path on the iPod, e.g. ":iPod_Control:Music:F00:ABCD.mp3"
    case album    = 3
    case artist   = 4
    case genre    = 5
    case filetype = 6
    case comment  = 8
    case composer = 12
    case grouping = 13
    case albumArtist = 22
    case sortArtist  = 23
}

/// A track as stored in the database.
struct ITunesDBTrack {
    var trackID: UInt32 = 0
    var title = ""
    var artist = ""
    var album = ""
    var albumArtist = ""
    var genre = ""
    var filetype = ""
    /// Colon-separated iPod path, e.g. ":iPod_Control:Music:F04:ABCD.mp3"
    var location = ""
    var sizeBytes: UInt32 = 0
    var durationMS: UInt32 = 0
    var trackNumber: UInt32 = 0
    var totalTracks: UInt32 = 0
    var year: UInt32 = 0
    var bitrate: UInt32 = 0
    var sampleRate: UInt32 = 0
    var dbid: UInt64 = 0

    /// Turns the iPod's colon path into a real filesystem path on the mounted
    /// volume.
    func fileURL(onVolume mount: String) -> URL? {
        guard !location.isEmpty else { return nil }
        let relative = location
            .replacingOccurrences(of: ":", with: "/")
        return URL(fileURLWithPath: mount + relative)
    }

    var durationSeconds: Double { Double(durationMS) / 1000 }
}

/// Little-endian reader that refuses to run off the end of the buffer — a
/// truncated or corrupt database should surface as an error, never a crash.
struct ByteReader {
    let bytes: [UInt8]
    var offset: Int = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var remaining: Int { bytes.count - offset }

    mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    mutating func u64() -> UInt64? {
        guard let low = u32(), let high = u32() else { return nil }
        return UInt64(low) | UInt64(high) << 32
    }

    mutating func magic() -> String? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
    }

    func peekMagic(at position: Int) -> String? {
        guard position + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[position..<position + 4], encoding: .ascii)
    }

    mutating func skip(_ count: Int) {
        offset = min(bytes.count, offset + count)
    }

    /// UTF-16LE, which is how iTunes stores every string in this format.
    func utf16String(at position: Int, byteLength: Int) -> String? {
        guard position >= 0, position + byteLength <= bytes.count, byteLength > 0 else { return nil }
        let slice = Data(bytes[position..<position + byteLength])
        return String(data: slice, encoding: .utf16LittleEndian)
    }
}

/// Little-endian writer used when building a database back out.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }
    var data: Data { Data(bytes) }

    mutating func ascii(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }

    mutating func u32(_ v: UInt32) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF))
        bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 24) & 0xFF))
    }

    mutating func u64(_ v: UInt64) {
        u32(UInt32(v & 0xFFFF_FFFF))
        u32(UInt32((v >> 32) & 0xFFFF_FFFF))
    }

    mutating func zeros(_ count: Int) {
        bytes.append(contentsOf: [UInt8](repeating: 0, count: count))
    }

    mutating func utf16(_ s: String) {
        for unit in Array(s.utf16) {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8((unit >> 8) & 0xFF))
        }
    }

    /// Back-patches a length once the real size is known — the format stores
    /// total lengths ahead of the content they describe.
    mutating func patchU32(at position: Int, _ v: UInt32) {
        guard position + 4 <= bytes.count else { return }
        bytes[position] = UInt8(v & 0xFF)
        bytes[position + 1] = UInt8((v >> 8) & 0xFF)
        bytes[position + 2] = UInt8((v >> 16) & 0xFF)
        bytes[position + 3] = UInt8((v >> 24) & 0xFF)
    }
}

enum ITunesDBError: LocalizedError {
    case notADatabase
    case truncated(String)
    case noFirewireID

    var errorDescription: String? {
        switch self {
        case .notADatabase: return "That file isn't an iTunes database."
        case .truncated(let where_): return "The database ends unexpectedly (in \(where_))."
        case .noFirewireID:
            return "Couldn't read this iPod's FireWire ID, which is needed to sign the database."
        }
    }
}
