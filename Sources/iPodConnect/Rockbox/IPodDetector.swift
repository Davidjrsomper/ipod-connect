import Foundation

/// Finds iPods mounted on this Mac. Everything here is read-only and needs
/// no privileges — an iPod in disk mode is just a mounted volume.
enum IPodDetector {

    static func scan() -> [ConnectedIPod] {
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? []
        var found: [ConnectedIPod] = []

        for name in volumes {
            let mount = "/Volumes/" + name
            let rockboxInfo = mount + "/.rockbox/rockbox-info.txt"
            let appleControl = mount + "/iPod_Control"

            let hasRockbox = fm.fileExists(atPath: rockboxInfo)
            let hasApple = fm.fileExists(atPath: appleControl)
            guard hasRockbox || hasApple else { continue }

            var target: String?
            var version: String?
            if hasRockbox, let info = try? String(contentsOfFile: rockboxInfo, encoding: .utf8) {
                (target, version) = parseRockboxInfo(info)
            }

            found.append(ConnectedIPod(
                id: mount,
                volumeName: name,
                mountPath: mount,
                bsdDisk: bsdDisk(forMountPoint: mount),
                installedTarget: target,
                installedVersion: version,
                hasAppleFirmware: hasApple
            ))
        }
        return found
    }

    /// `.rockbox/rockbox-info.txt` is `Key: Value` lines; we want Target and Version.
    static func parseRockboxInfo(_ text: String) -> (String?, String?) {
        var target: String?
        var version: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Target": target = parts[1]
            case "Version": version = parts[1]
            default: break
            }
        }
        return (target, version)
    }

    /// Maps a mount point to its whole-disk device (e.g. /dev/disk4), which is
    /// what ipodpatcher operates on.
    static func bsdDisk(forMountPoint mount: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", mount]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return nil }

        // Prefer the parent whole disk; the firmware partition lives outside
        // the mounted data partition.
        if let parent = dict["ParentWholeDisk"] as? String {
            return "/dev/" + parent
        }
        if let device = dict["DeviceIdentifier"] as? String {
            return "/dev/" + device
        }
        return nil
    }
}
