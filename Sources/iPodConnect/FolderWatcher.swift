import Foundation

/// Watches the music folder and reports when audio files appear, vanish or
/// move, so the library keeps up with the Finder without being told.
///
/// Uses FSEvents rather than polling: it's the same mechanism Spotlight and
/// Finder use, costs nothing while the folder is idle, and reports the whole
/// tree recursively — which matters when an album arrives as a new subfolder.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.davidsomper.ipodconnect.folderwatch")

    init?(path: String, onChange: @escaping () -> Void) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        // kFSEventStreamCreateFlagFileEvents reports individual files rather
        // than just "something in this directory changed", which lets us
        // ignore churn that isn't music.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let cPaths = paths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)
                as UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? else {
                watcher.onChange()
                return
            }
            for i in 0..<count {
                guard let raw = cPaths[i] else { continue }
                let path = String(cString: raw)
                let ext = (path as NSString).pathExtension.lowercased()
                // Only wake the library for audio; ignore .DS_Store and friends.
                if Library.audioExtensions.contains(ext) {
                    watcher.onChange()
                    return
                }
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,                    // coalesce bursts into one callback per second
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
