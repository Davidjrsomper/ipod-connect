import Foundation

/// A Rockbox build target. Names match the `rockbox-<target>-<version>.zip`
/// files on download.rockbox.org and the `target=` parameter of the theme API.
struct RockboxTarget: Identifiable, Hashable {
    let id: String          // e.g. "ipodvideo"
    let name: String        // e.g. "iPod Video (5G/5.5G)"
    let screen: String      // e.g. "320x240" — theme previews are per screen size
    /// Bootloader install route. The Classic needs DFU + libusb, which the
    /// app cannot drive; everything else goes through ipodpatcher.
    let bootloader: BootloaderRoute

    enum BootloaderRoute: Hashable {
        case ipodpatcher    // firmware partition patching, needs raw disk access
        case dfu            // iPod Classic 6G/7G: mks5lboot over USB DFU
    }

    static let all: [RockboxTarget] = [
        .init(id: "ipod1g2g",   name: "iPod 1G/2G",          screen: "160x128", bootloader: .ipodpatcher),
        .init(id: "ipod3g",     name: "iPod 3G",             screen: "160x128", bootloader: .ipodpatcher),
        .init(id: "ipod4g",     name: "iPod 4G (greyscale)", screen: "160x128", bootloader: .ipodpatcher),
        .init(id: "ipodcolor",  name: "iPod Color/Photo",    screen: "220x176", bootloader: .ipodpatcher),
        .init(id: "ipodvideo",  name: "iPod Video (5G/5.5G)", screen: "320x240", bootloader: .ipodpatcher),
        .init(id: "ipodmini1g", name: "iPod mini 1G",        screen: "138x110", bootloader: .ipodpatcher),
        .init(id: "ipodmini2g", name: "iPod mini 2G",        screen: "138x110", bootloader: .ipodpatcher),
        .init(id: "ipodnano1g", name: "iPod nano 1G",        screen: "176x132", bootloader: .ipodpatcher),
        .init(id: "ipodnano2g", name: "iPod nano 2G",        screen: "176x132", bootloader: .ipodpatcher),
        .init(id: "ipod6g",     name: "iPod Classic (6G/7G)", screen: "320x240", bootloader: .dfu),
    ]

    static func find(_ id: String) -> RockboxTarget? {
        all.first { $0.id == id }
    }
}

/// A theme from themes.rockbox.org.
struct RockboxTheme: Identifiable, Hashable {
    let id: String          // the INI section name
    let name: String
    let author: String
    let version: String
    let about: String
    let sizeBytes: Int
    let previewPath: String?    // relative, e.g. "/themes/320x240/foo/wps.png"
    let archivePath: String     // relative, e.g. "/download.php?themeid=4100"

    var previewURL: URL? {
        previewPath.flatMap { URL(string: RockboxCatalog.themesBase + $0) }
    }
    var archiveURL: URL? {
        URL(string: RockboxCatalog.themesBase + archivePath)
    }
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
    /// The theme's .cfg basename, used to make it the active theme.
    var configName: String { name }
}

/// An iPod found mounted on this Mac.
struct ConnectedIPod: Identifiable, Hashable {
    let id: String              // mount path
    let volumeName: String
    let mountPath: String
    let bsdDisk: String?        // e.g. "/dev/disk4"
    /// Set when .rockbox/rockbox-info.txt is present.
    let installedTarget: String?
    let installedVersion: String?
    /// True when iPod_Control exists — i.e. it really looks like an iPod.
    let hasAppleFirmware: Bool

    var isRockboxed: Bool { installedTarget != nil }

    var target: RockboxTarget? {
        installedTarget.flatMap { RockboxTarget.find($0) }
    }

    var statusText: String {
        if let version = installedVersion, let target {
            return "Rockbox \(version) · \(target.name)"
        }
        if isRockboxed, let version = installedVersion {
            return "Rockbox \(version)"
        }
        return hasAppleFirmware ? "Apple firmware — Rockbox not installed" : "Unknown device"
    }
}
