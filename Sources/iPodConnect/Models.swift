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

    /// Formats that carry every bit of the original recording. For these the
    /// meaningful number is bit depth and sample rate, not a bitrate — a FLAC
    /// rip varies in bitrate constantly without varying in quality.
    var isLossless: Bool {
        ["FLAC", "ALAC", "WAV", "AIFF", "AIF"].contains(format.uppercased())
    }

    /// Average bitrate in kbps, worked out from file size and duration.
    ///
    /// The raw figure runs a few percent high because tags and container
    /// overhead count toward file size, so a 320 kbps CBR rip measures
    /// anywhere from 320 to 335. Left alone, a library of identical rips
    /// displays a spray of meaningless numbers — so a result within 5% of a
    /// standard bitrate is reported as that bitrate. Anything further out is
    /// genuinely variable, and the measured average is the honest answer.
    var bitrateKbps: Int {
        guard duration > 0, fileSize > 0 else { return 0 }
        let measured = Double(fileSize) * 8 / duration / 1000
        let standard = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        if let match = standard.first(where: { abs(measured - Double($0)) / Double($0) <= 0.05 }) {
            return match
        }
        return Int(measured.rounded())
    }

    /// What goes in the Quality column.
    ///
    ///   FLAC/ALAC with known stream info → "16-bit · 44.1 kHz"
    ///   anything else                     → "320 kbps"
    var qualityText: String {
        if isLossless, sampleRate > 0, bitsPerSample > 0 {
            let khz = Double(sampleRate) / 1000
            let rate = khz == khz.rounded()
                ? String(format: "%.0f", khz)
                : String(format: "%.1f", khz)
            return "\(bitsPerSample)-bit · \(rate) kHz"
        }
        if isLossless, bitrateKbps > 0 { return "Lossless" }
        guard bitrateKbps > 0 else { return "—" }
        return "\(bitrateKbps) kbps"
    }

    /// Sorts lossless above lossy, then by resolution or bitrate within each.
    var qualityRank: Int {
        if isLossless, sampleRate > 0, bitsPerSample > 0 {
            return 1_000_000 + bitsPerSample * 1000 + sampleRate / 100
        }
        if isLossless { return 1_000_000 }
        return bitrateKbps
    }

    var timeString: String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum SortField: String, Codable {
    case name, time, artist, album, genre, kind, quality
}

enum RepeatMode {
    case off, all, one
}
