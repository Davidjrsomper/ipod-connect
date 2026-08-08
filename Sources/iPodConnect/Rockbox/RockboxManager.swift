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

    func loadThemes() async {
        isLoadingThemes = true
        themeError = nil
        defer { isLoadingThemes = false }
        do {
            themes = try await RockboxCatalog.fetchThemes(for: activeTarget)
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

    func removeBootloader() async {
        guard let device = selectedDevice, let disk = device.bsdDisk else { return }
        await run("Removing the bootloader…") {
            try RockboxInstaller.removeBootloader(device: disk)
            return "Bootloader removed. The iPod will boot Apple's firmware again."
        }
    }
}
