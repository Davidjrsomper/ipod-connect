import Foundation

struct Track: Identifiable, Codable, Hashable {
    var id: String { path }
    let path: String
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String
    var year: String
    var trackNumber: Int
    var discNumber: Int
    var duration: Double
    var sampleRate: Int
    var bitsPerSample: Int
    var fileSize: Int64
    var format: String

    var url: URL { URL(fileURLWithPath: path) }

    var sortArtist: String { albumArtist.isEmpty ? artist : albumArtist }

    var timeString: String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum SortField: String, Codable {
    case name, time, artist, album, genre
}

enum RepeatMode {
    case off, all, one
}
