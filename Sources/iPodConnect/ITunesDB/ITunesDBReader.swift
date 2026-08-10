import Foundation

/// Reads the track list out of a stock iPod's `iTunesDB`.
///
/// Deliberately forgiving: every chunk carries its own header and total
/// length, so anything unrecognised is skipped by length rather than treated
/// as an error. A database written by a newer iTunes than we know about still
/// parses, it just may carry fields we ignore.
enum ITunesDBReader {

    static func databaseURL(onVolume mount: String) -> URL {
        URL(fileURLWithPath: mount)
            .appendingPathComponent("iPod_Control/iTunes/iTunesDB")
    }

    static func databaseExists(onVolume mount: String) -> Bool {
        FileManager.default.fileExists(atPath: databaseURL(onVolume: mount).path)
    }

    static func read(volume mount: String) throws -> [ITunesDBTrack] {
        let url = databaseURL(onVolume: mount)
        guard let data = try? Data(contentsOf: url) else {
            throw ITunesDBError.notADatabase
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [ITunesDBTrack] {
        var reader = ByteReader(data)
        guard reader.peekMagic(at: 0) == ITunesDBChunk.database.rawValue else {
            throw ITunesDBError.notADatabase
        }

        // mhbd: magic, headerLen, totalLen …
        _ = reader.magic()
        guard let headerLen = reader.u32(), let _ = reader.u32() else {
            throw ITunesDBError.truncated("database header")
        }
        reader.offset = Int(headerLen)

        var tracks: [ITunesDBTrack] = []

        // Walk the datasets. Only type 1 holds tracks; playlists live in 2/3.
        while reader.remaining >= 12,
              reader.peekMagic(at: reader.offset) == ITunesDBChunk.dataset.rawValue {
            let datasetStart = reader.offset
            _ = reader.magic()
            guard let dsHeaderLen = reader.u32(),
                  let dsTotalLen = reader.u32(),
                  let type = reader.u32() else {
                throw ITunesDBError.truncated("dataset header")
            }

            if type == 1 {
                var inner = reader
                inner.offset = datasetStart + Int(dsHeaderLen)
                tracks = try parseTrackList(&inner)
            }

            // Skip to the next dataset by its declared length.
            guard dsTotalLen > 0 else { break }
            reader.offset = datasetStart + Int(dsTotalLen)
        }

        return tracks
    }

    private static func parseTrackList(_ reader: inout ByteReader) throws -> [ITunesDBTrack] {
        guard reader.peekMagic(at: reader.offset) == ITunesDBChunk.trackList.rawValue else {
            return []
        }
        // mhlt: magic, headerLen, songCount — note there's no total length here.
        _ = reader.magic()
        guard let headerLen = reader.u32(), let count = reader.u32() else {
            throw ITunesDBError.truncated("track list header")
        }
        reader.offset += Int(headerLen) - 12

        var tracks: [ITunesDBTrack] = []
        tracks.reserveCapacity(Int(min(count, 100_000)))

        for _ in 0..<count {
            guard reader.peekMagic(at: reader.offset) == ITunesDBChunk.track.rawValue else { break }
            guard let track = parseTrack(&reader) else { break }
            tracks.append(track)
        }
        return tracks
    }

    /// mhit — the track record. Field positions are relative to the chunk
    /// start, and read via the header length so unknown trailing fields in
    /// newer revisions don't shift anything.
    private static func parseTrack(_ reader: inout ByteReader) -> ITunesDBTrack? {
        let start = reader.offset
        _ = reader.magic()
        guard let headerLen = reader.u32(),
              let totalLen = reader.u32(),
              let mhodCount = reader.u32(),
              let trackID = reader.u32() else { return nil }

        var track = ITunesDBTrack()
        track.trackID = trackID

        func u32(atChunkOffset o: Int) -> UInt32 {
            var r = reader
            r.offset = start + o
            return r.u32() ?? 0
        }
        func u64(atChunkOffset o: Int) -> UInt64 {
            var r = reader
            r.offset = start + o
            return r.u64() ?? 0
        }

        // Offsets within mhit, from the chunk's first byte. Verified against
        // the iPodLinux format documentation rather than guessed.
        track.sizeBytes   = u32(atChunkOffset: 0x24)
        track.durationMS  = u32(atChunkOffset: 0x28)
        track.trackNumber = u32(atChunkOffset: 0x2C)
        track.totalTracks = u32(atChunkOffset: 0x30)
        track.year        = u32(atChunkOffset: 0x34)
        track.bitrate     = u32(atChunkOffset: 0x38)
        // Stored multiplied by 0x10000, so 44100 lands in the high 16 bits.
        track.sampleRate  = u32(atChunkOffset: 0x3C) >> 16
        track.totalDiscs  = u32(atChunkOffset: 0x60)
        // 0x70, not 0x60 — 0x60 is the disc count.
        track.dbid        = u64(atChunkOffset: 0x70)

        // The strings follow the fixed header as child mhod chunks.
        reader.offset = start + Int(headerLen)
        for _ in 0..<mhodCount {
            guard reader.peekMagic(at: reader.offset) == ITunesDBChunk.data.rawValue else { break }
            guard let (type, value) = parseMHOD(&reader) else { break }
            switch MHODType(rawValue: type) {
            case .title:       track.title = value
            case .location:    track.location = value
            case .album:       track.album = value
            case .artist:      track.artist = value
            case .genre:       track.genre = value
            case .filetype:    track.filetype = value
            case .albumArtist: track.albumArtist = value
            default: break     // composer, comments, sort keys… not needed here
            }
        }

        // Always advance by the chunk's declared size, whatever we understood.
        if totalLen > 0 { reader.offset = start + Int(totalLen) }
        return track
    }

    /// mhod — a typed blob. String types carry UTF-16LE text after a small
    /// sub-header; everything else is skipped.
    private static func parseMHOD(_ reader: inout ByteReader) -> (UInt32, String)? {
        let start = reader.offset
        _ = reader.magic()
        guard let headerLen = reader.u32(),
              let totalLen = reader.u32(),
              let type = reader.u32() else { return nil }

        defer {
            if totalLen > 0 { reader.offset = start + Int(totalLen) }
            else { reader.offset = start + Int(headerLen) }
        }

        // String payload: position, byte length, then the UTF-16LE data.
        var body = reader
        body.offset = start + Int(headerLen)
        guard body.remaining >= 16 else { return (type, "") }
        _ = body.u32()                              // unknown
        _ = body.u32()                              // unknown
        guard let byteLength = body.u32() else { return (type, "") }
        _ = body.u32()                              // unknown

        let textStart = body.offset
        let text = reader.utf16String(at: textStart, byteLength: Int(byteLength)) ?? ""
        return (type, text)
    }
}

// MARK: - Self-test

/// Builds a minimal but structurally valid iTunesDB and reads it back, so the
/// chunk walking and field offsets can be exercised without an iPod attached.
///
/// This proves the parser is self-consistent. It does **not** prove
/// compatibility with a database iTunes actually wrote — only a real device
/// can show that.
enum ITunesDBSelfTest {

    static func syntheticDatabase(tracks: [ITunesDBTrack]) -> Data {
        var w = ByteWriter()

        // mhbd
        w.ascii("mhbd"); w.u32(0x68)
        let dbTotalAt = w.count; w.u32(0)
        w.u32(1); w.u32(0x13); w.u32(1); w.u64(0)
        w.zeros(0x68 - w.count)

        // mhsd, type 1 (tracks)
        let dsStart = w.count
        w.ascii("mhsd"); w.u32(0x60)
        let dsTotalAt = w.count; w.u32(0)
        w.u32(1)
        w.zeros(dsStart + 0x60 - w.count)

        // mhlt
        w.ascii("mhlt"); w.u32(0x5C); w.u32(UInt32(tracks.count))
        w.zeros(0x5C - 12)

        for t in tracks {
            let trackStart = w.count
            let headerLen: UInt32 = 0x184
            w.ascii("mhit"); w.u32(headerLen)
            let totalAt = w.count; w.u32(0)
            w.u32(7)                      // mhod count written below
            w.u32(t.trackID)
            w.zeros(trackStart + 0x24 - w.count)
            w.u32(t.sizeBytes)            // 0x24
            w.u32(t.durationMS)           // 0x28
            w.u32(t.trackNumber)          // 0x2C
            w.u32(t.totalTracks)          // 0x30
            w.u32(t.year)                 // 0x34
            w.u32(t.bitrate)              // 0x38
            w.u32(t.sampleRate << 16)     // 0x3C
            w.zeros(trackStart + 0x60 - w.count)
            w.u32(t.totalDiscs)           // 0x60
            w.zeros(trackStart + 0x70 - w.count)
            w.u64(t.dbid)                 // 0x70
            w.zeros(trackStart + Int(headerLen) - w.count)

            func mhod(_ type: MHODType, _ value: String) {
                let start = w.count
                w.ascii("mhod"); w.u32(24)
                let totalAt = w.count; w.u32(0)
                w.u32(type.rawValue)
                w.u32(0); w.u32(0)                    // header padding to 24
                w.u32(1)                              // position
                w.u32(0)
                w.u32(UInt32(value.utf16.count * 2))  // byte length
                w.u32(0)
                w.utf16(value)
                w.patchU32(at: totalAt, UInt32(w.count - start))
            }
            mhod(.title, t.title)
            mhod(.location, t.location)
            mhod(.album, t.album)
            mhod(.artist, t.artist)
            mhod(.genre, t.genre)
            mhod(.filetype, t.filetype)
            mhod(.albumArtist, t.albumArtist)

            w.patchU32(at: totalAt, UInt32(w.count - trackStart))
        }

        w.patchU32(at: dsTotalAt, UInt32(w.count - dsStart))
        w.patchU32(at: dbTotalAt, UInt32(w.count))
        return w.data
    }

    static func run() -> Int32 {
        var a = ITunesDBTrack()
        a.trackID = 101; a.title = "Bad Guy"; a.artist = "Eminem"
        a.album = "The Marshall Mathers LP 2"; a.albumArtist = "Eminem"
        a.genre = "Hip-Hop"; a.filetype = "FLAC audio file"
        a.location = ":iPod_Control:Music:F04:ABCD.flac"
        a.sizeBytes = 34_512_900; a.durationMS = 434_100
        a.trackNumber = 1; a.totalTracks = 16; a.year = 2013
        a.bitrate = 940; a.sampleRate = 44100; a.dbid = 0x1234_5678_9ABC_DEF0
        a.totalDiscs = 1

        var b = ITunesDBTrack()
        b.trackID = 102; b.title = "Smells Like Teen Spirit"; b.artist = "Nirvana"
        b.album = "Nevermind"; b.albumArtist = "Nirvana"; b.genre = "Rock"
        b.filetype = "MPEG audio file"
        b.location = ":iPod_Control:Music:F11:WXYZ.mp3"
        b.sizeBytes = 7_212_000; b.durationMS = 301_300
        b.trackNumber = 1; b.totalTracks = 12; b.year = 1991
        b.bitrate = 192; b.sampleRate = 44100; b.dbid = 0x0FED_CBA9_8765_4321
        b.totalDiscs = 1

        let data = syntheticDatabase(tracks: [a, b])
        print("built a \(data.count)-byte database with 2 tracks")

        let parsed: [ITunesDBTrack]
        do { parsed = try ITunesDBReader.parse(data) }
        catch { print("PARSE FAILED: \(error.localizedDescription)"); return 1 }

        guard parsed.count == 2 else {
            print("FAIL: expected 2 tracks, parsed \(parsed.count)"); return 1
        }

        var failures = 0
        func check(_ label: String, _ got: String, _ want: String) {
            if got != want { print("  FAIL \(label): got \"\(got)\", want \"\(want)\""); failures += 1 }
        }
        func checkN(_ label: String, _ got: UInt64, _ want: UInt64) {
            if got != want { print("  FAIL \(label): got \(got), want \(want)"); failures += 1 }
        }

        for (got, want) in zip(parsed, [a, b]) {
            check("title", got.title, want.title)
            check("artist", got.artist, want.artist)
            check("album", got.album, want.album)
            check("albumArtist", got.albumArtist, want.albumArtist)
            check("genre", got.genre, want.genre)
            check("filetype", got.filetype, want.filetype)
            check("location", got.location, want.location)
            checkN("trackID", UInt64(got.trackID), UInt64(want.trackID))
            checkN("size", UInt64(got.sizeBytes), UInt64(want.sizeBytes))
            checkN("duration", UInt64(got.durationMS), UInt64(want.durationMS))
            checkN("trackNumber", UInt64(got.trackNumber), UInt64(want.trackNumber))
            checkN("totalTracks", UInt64(got.totalTracks), UInt64(want.totalTracks))
            checkN("year", UInt64(got.year), UInt64(want.year))
            checkN("bitrate", UInt64(got.bitrate), UInt64(want.bitrate))
            checkN("sampleRate", UInt64(got.sampleRate), UInt64(want.sampleRate))
            checkN("totalDiscs", UInt64(got.totalDiscs), UInt64(want.totalDiscs))
            checkN("dbid", got.dbid, want.dbid)
        }

        if failures == 0 {
            print("PASS: every field round-tripped")
            for t in parsed {
                print("  \(t.trackNumber). \(t.title) — \(t.artist) · \(t.album) "
                    + "(\(Int(t.durationSeconds))s, \(t.filetype))")
            }
        }
        return failures == 0 ? 0 : 1
    }
}
