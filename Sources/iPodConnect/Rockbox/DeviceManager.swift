import Foundation

@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var deviceTracks: [DeviceTrack] = []
    @Published private(set) var capacity: IPodSync.Capacity?
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressLabel = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var deviceSearch = ""

    var visibleDeviceTracks: [DeviceTrack] {
        let query = deviceSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return deviceTracks }
        return deviceTracks.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var deviceBytes: Int64 { deviceTracks.reduce(0) { $0 + $1.sizeBytes } }

    func refresh(mount: String?) {
        guard let mount else {
            deviceTracks = []
            capacity = nil
            return
        }
        deviceTracks = IPodSync.tracks(onVolume: mount)
        capacity = IPodSync.capacity(ofVolume: mount)
    }

    /// Copies tracks to the device, checking there's room first.
    func copy(_ tracks: [Track], toMount mount: String) async {
        guard !tracks.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false; progress = 0; progressLabel = "" }

        let needed = IPodSync.bytesRequired(for: tracks, onVolume: mount)
        if let capacity, needed > capacity.freeBytes {
            let short = ByteCountFormatter.string(
                fromByteCount: needed - capacity.freeBytes, countStyle: .file)
            errorMessage = "Not enough space — \(short) more needed. Nothing was copied."
            return
        }

        var copied = 0, skipped = 0
        var failures: [String] = []
        for (index, track) in tracks.enumerated() {
            progress = Double(index) / Double(tracks.count)
            progressLabel = "Copying \(index + 1) of \(tracks.count) — \(track.title)"
            switch IPodSync.copy(track, toVolume: mount) {
            case .copied: copied += 1
            case .skippedExisting: skipped += 1
            case .failed(let reason):
                failures.append("\(track.title): \(reason)")
            }
            await Task.yield()
        }

        refresh(mount: mount)
        var parts: [String] = []
        if copied > 0 { parts.append("\(copied) copied") }
        if skipped > 0 { parts.append("\(skipped) already on the iPod") }
        if !failures.isEmpty { parts.append("\(failures.count) failed") }
        statusMessage = parts.joined(separator: " · ") + ". Eject before unplugging."
        if !failures.isEmpty { errorMessage = failures.prefix(3).joined(separator: "\n") }
    }

    func remove(_ tracks: [DeviceTrack], fromMount mount: String) async {
        guard !tracks.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false; progress = 0; progressLabel = "" }

        var removed = 0
        var failures: [String] = []
        for (index, track) in tracks.enumerated() {
            progress = Double(index) / Double(tracks.count)
            progressLabel = "Removing \(index + 1) of \(tracks.count)"
            do {
                try IPodSync.remove(track, fromVolume: mount)
                removed += 1
            } catch {
                failures.append("\(track.name): \(error.localizedDescription)")
            }
            await Task.yield()
        }

        refresh(mount: mount)
        statusMessage = "\(removed) removed from the iPod."
        if !failures.isEmpty { errorMessage = failures.prefix(3).joined(separator: "\n") }
    }

    func eject(mount: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", mount]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            statusMessage = "iPod ejected — safe to unplug."
            deviceTracks = []
            capacity = nil
        } else {
            errorMessage = "Couldn't eject. Close anything using the iPod and try again."
        }
    }
}
