import Foundation
import AVFoundation
import AppKit
import MediaPlayer

@MainActor
final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.75 {
        didSet { audioPlayer?.volume = Float(volume) }
    }

    private var audioPlayer: AVAudioPlayer?
    private var queue: [Track] = []
    private var timer: Timer?
    private var history: [Track] = []

    override init() {
        super.init()
        setUpRemoteCommands()
    }

    var duration: Double { current?.duration ?? 0 }

    // MARK: - Transport

    func play(track: Track, in list: [Track]) {
        queue = list
        start(track)
    }

    func togglePlayPause() {
        guard let audioPlayer else {
            if let first = queue.first ?? current { start(first) }
            return
        }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
        } else {
            audioPlayer.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func next() {
        guard let track = nextTrack() else { stop(); return }
        start(track)
    }

    func previous() {
        if elapsed > 3 { seek(to: 0); return }
        if shuffle, history.count > 1 {
            history.removeLast()
            if let prior = history.popLast() { start(prior); return }
        }
        guard let current, let idx = queue.firstIndex(of: current), idx > 0 else { seek(to: 0); return }
        start(queue[idx - 1])
    }

    func seek(to time: Double) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = max(0, min(time, audioPlayer.duration - 0.1))
        elapsed = audioPlayer.currentTime
        updateNowPlaying()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        elapsed = 0
        timer?.invalidate()
        timer = nil
        updateNowPlaying()
    }

    private func start(_ track: Track) {
        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            player.delegate = self
            player.volume = Float(volume)
            audioPlayer = player
            current = track
            elapsed = 0
            player.play()
            isPlaying = true
            history.append(track)
            if history.count > 500 { history.removeFirst(250) }
            startTimer()
            updateNowPlaying()
        } catch {
            NSSound.beep()
        }
    }

    private func nextTrack() -> Track? {
        guard let current else { return queue.first }
        if repeatMode == .one { return current }
        if shuffle {
            let others = queue.filter { $0 != current }
            return others.randomElement() ?? (repeatMode == .all ? current : nil)
        }
        guard let idx = queue.firstIndex(of: current) else { return queue.first }
        if idx + 1 < queue.count { return queue[idx + 1] }
        return repeatMode == .all ? queue.first : nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let audioPlayer = self.audioPlayer else { return }
                self.elapsed = audioPlayer.currentTime
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }

    // MARK: - Now Playing / media keys

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard let current else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album,
            MPMediaItemPropertyPlaybackDuration: current.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let image = ArtworkLoader.shared.cached(for: current) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }
}

// MARK: - Artwork

final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()
    private let cache = NSCache<NSString, NSImage>()
    private let missing = NSCache<NSString, NSNumber>()

    func cached(for track: Track) -> NSImage? {
        cache.object(forKey: track.path as NSString)
    }

    func artwork(for track: Track) async -> NSImage? {
        let key = track.path as NSString
        if let image = cache.object(forKey: key) { return image }
        if missing.object(forKey: key) != nil { return nil }

        let image: NSImage? = await Task.detached(priority: .utility) {
            // Artwork the user supplied by hand wins over anything embedded.
            let store = ArtworkStore.shared
            if let img = store.image(forKey: ArtworkStore.trackKey(path: track.path)) {
                return img
            }
            let albumArtist = track.albumArtist.isEmpty ? track.artist : track.albumArtist
            if let img = store.image(forKey: ArtworkStore.albumKey(artist: albumArtist, album: track.album)) {
                return img
            }

            if track.format == "FLAC", let data = FLACParser.artwork(url: track.url), let img = NSImage(data: data) {
                return img
            }
            // Embedded artwork via AVFoundation for other formats.
            let asset = AVURLAsset(url: track.url)
            if let items = try? await asset.load(.metadata) {
                for item in items where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue), let img = NSImage(data: data) {
                        return img
                    }
                }
            }
            // Fall back to a cover image next to the file.
            let dir = track.url.deletingLastPathComponent()
            for name in ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "Cover.jpg", "artwork.jpg"] {
                let candidate = dir.appendingPathComponent(name)
                if let img = NSImage(contentsOf: candidate) { return img }
            }
            return nil
        }.value

        if let image { cache.setObject(image, forKey: key) }
        else { missing.setObject(1, forKey: key) }
        return image
    }

    /// Called after the user adds artwork, so the affected tracks are looked
    /// up again instead of returning the cached "no artwork" answer.
    func invalidate(paths: [String]) {
        for path in paths {
            let key = path as NSString
            cache.removeObject(forKey: key)
            missing.removeObject(forKey: key)
        }
    }
}
