import Foundation
import AVFoundation
import AppKit

enum LibrarySource {
    case music, artists, albums, rockbox
}

enum MusicViewMode {
    case list, coverFlow
}

struct AlbumGroup: Identifiable {
    let artist: String
    let album: String
    let year: String
    let genre: String
    let tracks: [Track]
    var id: String { artist + "|" + album }
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanCount = 0
    @Published var folderPath: String?
    @Published var searchText = ""
    @Published var sortField: SortField = .artist
    @Published var sortAscending = true
    @Published var source: LibrarySource = .music
    @Published var selectedArtist: String?
    @Published var ipodMode = false
    @Published var musicViewMode: MusicViewMode = .list
    @Published var showMissingArtwork = false
    /// Bumped whenever the user adds artwork, so art views reload.
    @Published var artworkVersion = 0

    nonisolated static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "aiff", "aif", "ogg", "opus"]

    private var scanTask: Task<Void, Never>?

    // MARK: - Derived state

    var visibleTracks: [Track] {
        var result = tracks
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.artist.localizedCaseInsensitiveContains(query)
                    || $0.album.localizedCaseInsensitiveContains(query)
            }
        }
        result.sort { a, b in sortAscending ? isOrdered(a, b) : isOrdered(b, a) }
        return result
    }

    private func isOrdered(_ a: Track, _ b: Track) -> Bool {
        func albumOrder(_ x: Track, _ y: Track) -> Bool? {
            let album = x.album.localizedStandardCompare(y.album)
            if album != .orderedSame { return album == .orderedAscending }
            if x.discNumber != y.discNumber { return x.discNumber < y.discNumber }
            if x.trackNumber != y.trackNumber { return x.trackNumber < y.trackNumber }
            return nil
        }
        switch sortField {
        case .name:
            let r = a.title.localizedStandardCompare(b.title)
            if r != .orderedSame { return r == .orderedAscending }
        case .time:
            if a.duration != b.duration { return a.duration < b.duration }
        case .artist:
            let r = a.sortArtist.localizedStandardCompare(b.sortArtist)
            if r != .orderedSame { return r == .orderedAscending }
            if let o = albumOrder(a, b) { return o }
        case .album:
            if let o = albumOrder(a, b) { return o }
        case .genre:
            let r = a.genre.localizedStandardCompare(b.genre)
            if r != .orderedSame { return r == .orderedAscending }
            if let o = albumOrder(a, b) { return o }
        case .kind:
            let r = a.format.localizedStandardCompare(b.format)
            if r != .orderedSame { return r == .orderedAscending }
            if let o = albumOrder(a, b) { return o }
        }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    func setSort(_ field: SortField) {
        if sortField == field { sortAscending.toggle() }
        else { sortField = field; sortAscending = true }
    }

    // MARK: - Artist browsing

    private func displayArtist(_ track: Track) -> String {
        track.sortArtist.isEmpty ? "Unknown Artist" : track.sortArtist
    }

    /// Filing name, iTunes-style: "The Beatles" sorts under B.
    nonisolated private static func filingName(_ name: String) -> String {
        let lower = name.lowercased()
        for prefix in ["the ", "a ", "an "] where lower.hasPrefix(prefix) && name.count > prefix.count {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    var allArtists: [String] {
        Set(tracks.map { displayArtist($0) }).sorted {
            Self.filingName($0).localizedStandardCompare(Self.filingName($1)) == .orderedAscending
        }
    }

    var visibleArtists: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allArtists }
        return allArtists.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var songsByTitle: [Track] {
        tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func makeAlbumGroups(from pool: [Track], groupByArtist: Bool) -> [AlbumGroup] {
        var grouped: [String: [Track]] = [:]
        for track in pool {
            grouped[displayArtist(track) + "|" + track.album, default: []].append(track)
        }

        var groups: [AlbumGroup] = grouped.map { _, albumTracks in
            let sorted = albumTracks.sorted {
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let first = sorted[0]
            return AlbumGroup(
                artist: displayArtist(first),
                album: first.album,
                year: sorted.first(where: { !$0.year.isEmpty })?.year ?? "",
                genre: sorted.first(where: { !$0.genre.isEmpty })?.genre ?? "",
                tracks: sorted
            )
        }

        groups.sort { a, b in
            if groupByArtist {
                let r = Self.filingName(a.artist).localizedStandardCompare(Self.filingName(b.artist))
                if r != .orderedSame { return r == .orderedAscending }
                if a.year != b.year { return a.year < b.year }
            }
            return a.album.localizedStandardCompare(b.album) == .orderedAscending
        }
        return groups
    }

    /// Albums for one artist, or for every visible artist when `artist` is nil.
    func albumGroups(for artist: String?) -> [AlbumGroup] {
        if let artist {
            return makeAlbumGroups(
                from: tracks.filter { displayArtist($0) == artist },
                groupByArtist: false
            )
        }
        let allowed = Set(visibleArtists)
        return makeAlbumGroups(
            from: tracks.filter { allowed.contains(displayArtist($0)) },
            groupByArtist: true
        )
    }

    /// Every album, ignoring the search field — used by the iPod's Albums menu.
    var allAlbums: [AlbumGroup] {
        makeAlbumGroups(from: tracks, groupByArtist: false)
    }

    /// Albums matching the search field, sorted by album title.
    var visibleAlbums: [AlbumGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allAlbums }
        return allAlbums.filter {
            $0.album.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    var totalDuration: Double { tracks.reduce(0) { $0 + $1.duration } }
    var totalBytes: Int64 { tracks.reduce(0) { $0 + $1.fileSize } }

    var statusText: String {
        if isScanning { return "Scanning… \(scanCount) songs found" }
        guard !tracks.isEmpty else { return "No songs" }
        let count = NumberFormatter.localizedString(from: NSNumber(value: tracks.count), number: .decimal)
        let bytes = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(count) songs, \(durationText(totalDuration)), \(bytes)"
    }

    private func durationText(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 48 { return String(format: "%.1f days", hours / 24) }
        if hours >= 1 { return String(format: "%.1f hours", hours) }
        return String(format: "%.0f minutes", seconds / 60)
    }

    // MARK: - Folder selection & scanning

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your music folder. iPod Connect will scan it for FLAC and other audio files."
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            rescan()
        }
    }

    func rescan() {
        guard let folderPath else { return }
        scanTask?.cancel()
        scanTask = Task { await scan(folder: URL(fileURLWithPath: folderPath)) }
    }

    private func scan(folder: URL) async {
        isScanning = true
        scanCount = 0
        defer { isScanning = false }

        let files: [URL] = await Task.detached(priority: .userInitiated) {
            var found: [URL] = []
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let file = enumerator?.nextObject() as? URL {
                if Library.audioExtensions.contains(file.pathExtension.lowercased()) {
                    found.append(file)
                }
            }
            return found
        }.value

        guard !Task.isCancelled else { return }

        var newTracks: [Track] = []
        await withTaskGroup(of: Track?.self) { group in
            var iterator = files.makeIterator()
            func addNext() {
                if let file = iterator.next() {
                    group.addTask { await Self.makeTrack(url: file) }
                }
            }
            for _ in 0..<8 { addNext() }
            for await track in group {
                if let track {
                    newTracks.append(track)
                    scanCount = newTracks.count
                    if newTracks.count % 200 == 0 { tracks = newTracks }
                }
                if Task.isCancelled { break }
                addNext()
            }
        }

        guard !Task.isCancelled else { return }
        tracks = newTracks
        save()
    }

    nonisolated private static func makeTrack(url: URL) async -> Track? {
        let path = url.path
        let ext = url.pathExtension.lowercased()
        let fileName = url.deletingPathExtension().lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0

        if ext == "flac", let info = FLACParser.parse(url: url) {
            return Track(
                path: path,
                title: info.title ?? fileName,
                artist: info.artist ?? "Unknown Artist",
                album: info.album ?? "Unknown Album",
                albumArtist: info.albumArtist ?? "",
                genre: info.genre ?? "",
                year: info.date.map { String($0.prefix(4)) } ?? "",
                trackNumber: info.trackNumber ?? 0,
                discNumber: info.discNumber ?? 0,
                duration: info.duration,
                sampleRate: info.sampleRate,
                bitsPerSample: info.bitsPerSample,
                fileSize: size,
                format: "FLAC"
            )
        }

        // Everything else goes through AVFoundation.
        let asset = AVURLAsset(url: url)
        var title = fileName, artist = "Unknown Artist", album = "Unknown Album"
        var albumArtist = "", genre = "", year = "", duration = 0.0
        var trackNumber = 0, discNumber = 0
        if let d = try? await asset.load(.duration) { duration = d.seconds.isFinite ? d.seconds : 0 }
        if let items = try? await asset.load(.metadata) {
            for item in items {
                if let key = item.commonKey {
                    switch key {
                    case .commonKeyTitle: if let v = try? await item.load(.stringValue) { title = v }
                    case .commonKeyArtist: if let v = try? await item.load(.stringValue) { artist = v }
                    case .commonKeyAlbumName: if let v = try? await item.load(.stringValue) { album = v }
                    default: break
                    }
                    continue
                }
                guard let id = item.identifier else { continue }
                switch id {
                case .id3MetadataContentType, .iTunesMetadataUserGenre:
                    if let v = try? await item.load(.stringValue) { genre = v }
                case .id3MetadataTrackNumber:
                    if let v = try? await item.load(.stringValue),
                       let n = Int(v.split(separator: "/").first.map(String.init) ?? v) { trackNumber = n }
                case .iTunesMetadataTrackNumber:
                    if let d = try? await item.load(.dataValue), d.count >= 4 {
                        let b = [UInt8](d)
                        trackNumber = Int(b[2]) << 8 | Int(b[3])
                    }
                case .id3MetadataPartOfASet:
                    if let v = try? await item.load(.stringValue),
                       let n = Int(v.split(separator: "/").first.map(String.init) ?? v) { discNumber = n }
                case .iTunesMetadataDiscNumber:
                    if let d = try? await item.load(.dataValue), d.count >= 4 {
                        let b = [UInt8](d)
                        discNumber = Int(b[2]) << 8 | Int(b[3])
                    }
                case .id3MetadataBand, .iTunesMetadataAlbumArtist:
                    if let v = try? await item.load(.stringValue) { albumArtist = v }
                case .id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate:
                    if let v = try? await item.load(.stringValue), !v.isEmpty, year.isEmpty {
                        year = String(v.prefix(4))
                    }
                default: break
                }
            }
        }
        guard duration > 0 else { return nil }
        return Track(
            path: path, title: title, artist: artist, album: album, albumArtist: albumArtist,
            genre: genre, year: year, trackNumber: trackNumber, discNumber: discNumber,
            duration: duration, sampleRate: 0, bitsPerSample: 0,
            fileSize: size, format: ext.uppercased()
        )
    }

    // MARK: - Persistence

    private struct SavedLibrary: Codable {
        var folderPath: String?
        var tracks: [Track]
    }

    private static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPod Connect", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    func save() {
        let saved = SavedLibrary(folderPath: folderPath, tracks: tracks)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: Self.saveURL, options: .atomic)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.saveURL),
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        folderPath = saved.folderPath
        tracks = saved.tracks.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
