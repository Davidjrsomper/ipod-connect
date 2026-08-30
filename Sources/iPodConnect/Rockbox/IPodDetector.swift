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

            let disk = bsdDisk(forMountPoint: mount)

            found.append(ConnectedIPod(
                id: mount,
                volumeName: name,
                mountPath: mount,
                bsdDisk: disk,
                installedTarget: target,
                installedVersion: version,
                hasAppleFirmware: hasApple,
                fileSystem: fileSystemType(forMountPoint: mount),
                bsdVolume: bsdVolume(forMountPoint: mount),
                partitionScheme: disk.flatMap(partitionScheme(forWholeDisk:))
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

    /// The volume's own device node (e.g. /dev/disk4s2) — as opposed to the
    /// whole disk. Erasing this reformats the music partition and leaves the
    /// firmware partition, which holds the bootloader, untouched.
    static func bsdVolume(forMountPoint mount: String) -> String? {
        guard let id = diskutilInfo(for: mount)?["DeviceIdentifier"] as? String
        else { return nil }
        return "/dev/" + id
    }

    /// diskutil's FilesystemType for a mount point, e.g. "msdos" or "hfs".
    static func fileSystemType(forMountPoint mount: String) -> String? {
        diskutilInfo(for: mount)?["FilesystemType"] as? String
    }

    /// The whole disk's partition scheme: "FDisk_partition_scheme" (PC/MBR),
    /// "Apple_partition_scheme" (APM) or "GUID_partition_scheme" (GPT).
    ///
    /// Deliberately read from the whole disk, not the volume. The scheme is a
    /// property of the disk, and it is what the Rockbox bootloader actually
    /// parses. A volume can report FAT32 while the disk around it still
    /// carries an Apple partition map, and that combination is exactly what
    /// boots to "No partition found".
    static func partitionScheme(forWholeDisk disk: String) -> String? {
        diskutilInfo(for: disk)?["Content"] as? String
    }

    /// Takes anything diskutil accepts: a mount point or a /dev node.
    private static func diskutilInfo(for target: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", target]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    /// Maps a mount point to its whole-disk device (e.g. /dev/disk4), which is
    /// what ipodpatcher operates on.
    static func bsdDisk(forMountPoint mount: String) -> String? {
        guard let dict = diskutilInfo(for: mount) else { return nil }

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
