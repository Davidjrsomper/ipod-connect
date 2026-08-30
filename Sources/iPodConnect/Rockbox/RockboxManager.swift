import Foundation
import AppKit

@MainActor
final class RockboxManager: ObservableObject {
    @Published private(set) var devices: [ConnectedIPod] = []
    @Published var selectedDeviceID: String?
    /// Chosen manually when the iPod isn't Rockboxed yet, so we can't read
    /// its target from the device.
    @Published var manualTarget: RockboxTarget = RockboxTarget.find("ipodvideo")!

    @Published private(set) var themes: [RockboxTheme] = []
    @Published private(set) var isLoadingThemes = false
    @Published private(set) var themeError: String?
    @Published var themeSearch = ""

    @Published private(set) var installedThemes: [String] = []
    @Published private(set) var activeTheme: String?

    @Published private(set) var busyMessage: String?
    @Published private(set) var progress: Double = 0
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    /// True while we're waiting for the user to put a Classic into DFU mode.
    @Published private(set) var waitingForDFU = false

    private var previewCache: [String: NSImage] = [:]

    var selectedDevice: ConnectedIPod? {
        devices.first { $0.id == selectedDeviceID } ?? devices.first
    }

    /// The target to browse themes for: the device's own if Rockboxed,
    /// otherwise whatever the user picked.
    var activeTarget: RockboxTarget {
        selectedDevice?.target ?? manualTarget
    }

    var isBusy: Bool { busyMessage != nil }

    /// Things that will make a bootloader install fail *after* it appears to
    /// succeed. Both are common enough to be worth catching up front rather
    /// than leaving someone with an iPod that won't boot.
    enum PreflightIssue: Identifiable {
        case wrongPartitionMap(String)
        case notFAT32(String)
        case rockboxMissing

        var id: String {
            switch self {
            case .wrongPartitionMap: return "partitionmap"
            case .notFAT32: return "fat32"
            case .rockboxMissing: return "rockbox"
            }
        }

        var title: String {
            switch self {
            case .wrongPartitionMap(let scheme):
                return "This iPod uses \(scheme), not a PC partition table"
            case .notFAT32(let fs): return "This iPod is formatted \(fs), not FAT32"
            case .rockboxMissing: return "Rockbox isn't on this iPod yet"
            }
        }

        var detail: String {
            switch self {
            case .wrongPartitionMap:
                return "The bootloader reads a PC (MBR) partition table, so it can't see this disk at all — it will install, then stop at “No partition found”. Formatting as FAT32 won't help, because that works inside the existing partition map and leaves it in place. Use Convert to FAT32 instead: it rewrites the map and reformats in one step, and keeps any bootloader already installed. This erases the iPod."
            case .notFAT32:
                return "Rockbox can only read FAT32. The bootloader will install, then fail to start, because it can't read the disk to find Rockbox. Use Format as FAT32 first — this erases the iPod, so copy anything you want to keep off the device beforehand."
            case .rockboxMissing:
                return "The bootloader starts Rockbox, but Rockbox itself isn't installed. Install it first with the button above, then install the bootloader — otherwise the iPod boots to a blank screen or falls back to Apple's firmware."
            }
        }
    }

    /// Checked before flashing anything.
    var preflightIssues: [PreflightIssue] {
        guard let device = selectedDevice else { return [] }
        var issues: [PreflightIssue] = []
        // A wrong partition map subsumes a wrong filesystem: converting fixes
        // both, so raising them separately would ask for two actions when only
        // one exists.
        if !device.hasBootablePartitionMap {
            issues.append(.wrongPartitionMap(device.partitionSchemeName))
        } else if device.fileSystem != nil && !device.isFAT32 {
            issues.append(.notFAT32(device.fileSystemName))
        }
        if !device.isRockboxed {
            issues.append(.rockboxMissing)
        }
        return issues
    }

    var visibleThemes: [RockboxTheme] {
        let query = themeSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return themes }
        return themes.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.author.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Devices

    func refreshDevices() {
        devices = IPodDetector.scan()
        if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first?.id
        }
        refreshDeviceThemes()
    }

    func refreshDeviceThemes() {
        guard let device = selectedDevice, device.isRockboxed else {
            installedThemes = []
            activeTheme = nil
            return
        }
        installedThemes = RockboxInstaller.installedThemes(onVolume: device.mountPath)
        activeTheme = RockboxInstaller.activeTheme(onVolume: device.mountPath)
    }

    // MARK: Themes

    func loadThemes(forceRefresh: Bool = false) async {
        isLoadingThemes = true
        themeError = nil
        defer { isLoadingThemes = false }
        do {
            themes = try await RockboxCatalog.fetchThemes(
                for: activeTarget, forceRefresh: forceRefresh)
        } catch {
            themes = []
            themeError = error.localizedDescription
        }
    }

    func preview(for theme: RockboxTheme) -> NSImage? { previewCache[theme.id] }

    func loadPreview(for theme: RockboxTheme) async {
        guard previewCache[theme.id] == nil, let url = theme.previewURL else { return }
        guard let data = try? await RockboxCatalog.fetchPreview(url),
              let image = NSImage(data: data) else { return }
        previewCache[theme.id] = image
    }

    // MARK: Operations

    private func run(_ message: String, _ work: @escaping () async throws -> String) async {
        busyMessage = message
        progress = 0
        errorMessage = nil
        statusMessage = nil
        defer { busyMessage = nil; progress = 0 }
        do {
            statusMessage = try await work()
        } catch RockboxError.cancelled {
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshDevices()
    }

    func installFirmware() async {
        guard let device = selectedDevice else { errorMessage = RockboxError.noDevice.localizedDescription; return }
        let target = activeTarget
        guard let url = RockboxCatalog.buildURL(for: target) else { return }

        await run("Installing Rockbox \(RockboxCatalog.release) for \(target.name)…") {
            let archive = try await RockboxCatalog.download(url) { fraction in
                Task { @MainActor in self.progress = fraction * 0.8 }
            }
            await MainActor.run { self.progress = 0.85 }
            try RockboxInstaller.unzip(archive, toVolume: device.mountPath)
            try? FileManager.default.removeItem(at: archive)
            return "Rockbox \(RockboxCatalog.release) installed to \(device.volumeName). Eject the iPod before unplugging."
        }
    }

    func install(theme: RockboxTheme, activate: Bool) async {
        guard let device = selectedDevice else { errorMessage = RockboxError.noDevice.localizedDescription; return }
        guard device.isRockboxed else { errorMessage = RockboxError.notRockboxed.localizedDescription; return }
        guard let url = theme.archiveURL else { return }

        await run("Installing “\(theme.name)”…") {
            let archive = try await RockboxCatalog.download(url) { fraction in
                Task { @MainActor in self.progress = fraction * 0.8 }
            }
            await MainActor.run { self.progress = 0.85 }
            try RockboxInstaller.unzip(archive, toVolume: device.mountPath)
            try? FileManager.default.removeItem(at: archive)
            if activate {
                try RockboxInstaller.activateTheme(named: theme.configName, onVolume: device.mountPath)
                return "“\(theme.name)” installed and set as the active theme."
            }
            return "“\(theme.name)” installed. Pick it on the iPod under Settings → Theme Settings."
        }
    }

    func activate(themeNamed name: String) {
        guard let device = selectedDevice else { return }
        do {
            try RockboxInstaller.activateTheme(named: name, onVolume: device.mountPath)
            statusMessage = "Switched to “\(name)”. Restart the iPod to see it."
            refreshDeviceThemes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Formatting

    /// Erases the iPod's music partition and reformats it as FAT32. The
    /// firmware partition is left alone, so a bootloader already installed
    /// survives. Destructive, so the UI makes the user type the iPod's name.
    func formatAsFAT32() async {
        guard let device = selectedDevice else {
            errorMessage = RockboxError.noDevice.localizedDescription
            return
        }
        guard let volume = device.bsdVolume else {
            errorMessage = "Couldn't work out which partition to format."
            return
        }
        let name = device.volumeName

        await run("Formatting \(name) as FAT32…") {
            try RockboxInstaller.formatAsFAT32(volume: volume, name: name)
            // Give the volume a moment to remount under its new name.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return "Formatted as FAT32. Install Rockbox next, then the bootloader."
        }
    }

    /// Rewrites a Mac-partitioned iPod's partition map as a PC (MBR) one and
    /// reformats it as FAT32, which `formatAsFAT32` cannot do. Needs raw disk
    /// access, so unlike formatting it asks for an administrator password.
    func convertToFAT32() async {
        guard let device = selectedDevice else {
            errorMessage = RockboxError.noDevice.localizedDescription
            return
        }
        guard let disk = device.bsdDisk else {
            errorMessage = "Couldn't work out which disk this iPod is."
            return
        }

        await run("Converting \(device.volumeName) to FAT32…") {
            try RockboxInstaller.convertToFAT32(disk: disk)
            return "Converted to FAT32. Unplug the iPod and plug it back in, then install Rockbox."
        }
    }

    // MARK: Bootloader

    func installBootloader() async {
        guard let device = selectedDevice else { errorMessage = RockboxError.noDevice.localizedDescription; return }
        guard let disk = device.bsdDisk else {
            errorMessage = "Couldn't work out which disk this iPod is."
            return
        }
        let target = activeTarget
        guard target.bootloader == .ipodpatcher, let url = RockboxCatalog.bootloaderURL(for: target) else {
            errorMessage = "\(target.name) needs the DFU installer — see the instructions in this panel."
            return
        }

        await run("Installing the bootloader on \(disk)…") {
            let file = try await RockboxCatalog.download(url) { fraction in
                Task { @MainActor in self.progress = fraction * 0.5 }
            }
            await MainActor.run { self.progress = 0.6 }
            let backup = try RockboxInstaller.installBootloader(
                device: disk, bootloader: file, deviceLabel: device.volumeName)
            try? FileManager.default.removeItem(at: file)
            return "Bootloader installed. Firmware backed up to \(backup.lastPathComponent)."
        }
    }

    /// iPod Classic 6G/7G. Downloads the bootloader, waits for the user to
    /// hold the button combo, then writes it over USB. No admin password:
    /// mks5lboot reaches the device through IOKit.
    func installClassicBootloader() async {
        let target = activeTarget
        guard target.bootloader == .dfu, let url = RockboxCatalog.bootloaderURL(for: target) else {
            errorMessage = "\(target.name) doesn't use the DFU installer."
            return
        }

        await run("Installing the bootloader on your \(target.name)…") {
            let file = try await RockboxCatalog.download(url) { fraction in
                Task { @MainActor in self.progress = fraction * 0.3 }
            }
            defer { try? FileManager.default.removeItem(at: file) }

            await MainActor.run {
                self.waitingForDFU = true
                self.progress = 0.35
            }
            defer { Task { @MainActor in self.waitingForDFU = false } }

            // Poll for the device appearing in DFU mode. Two minutes is
            // generous: the button combo often takes a couple of attempts.
            let deadline = Date().addingTimeInterval(120)
            var found = false
            while Date() < deadline {
                if RockboxInstaller.isIPodInDFUMode() { found = true; break }
                try? await Task.sleep(nanoseconds: 1000000000)
            }
            guard found else {
                throw RockboxError.patcherFailed(
                    "Timed out waiting for the iPod to enter DFU mode. Hold MENU and SELECT together until the screen goes blank, and keep holding.")
            }

            await MainActor.run { self.progress = 0.7 }
            try RockboxInstaller.installClassicBootloader(bootloader: file)
            return "Bootloader installed. Disconnect the iPod and it should start into Rockbox."
        }
    }

    func removeBootloader() async {
        guard let device = selectedDevice, let disk = device.bsdDisk else { return }
        await run("Removing the bootloader…") {
            try RockboxInstaller.removeBootloader(device: disk)
            return "Bootloader removed. The iPod will boot Apple's firmware again."
        }
    }
}
