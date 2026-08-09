import Foundation

/// Performs the actual installs. File operations go straight to the mounted
/// volume and need no privileges; the bootloader step needs raw disk access
/// and therefore an administrator prompt.
enum RockboxInstaller {

    // MARK: Firmware & themes (no privileges required)

    /// Unzips an archive into the iPod's volume root. Both Rockbox builds and
    /// themes are packaged with a top-level `.rockbox/`, so extracting at the
    /// root is correct for each.
    static func unzip(_ archive: URL, toVolume mount: String) throws {
        guard FileManager.default.fileExists(atPath: mount) else {
            throw RockboxError.noDevice
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // ditto -x -k handles zip and preserves the directory tree.
        process.arguments = ["-x", "-k", archive.path, mount]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RockboxError.unzipFailed(
                String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "exit \(process.terminationStatus)")
        }
    }

    /// Lists the theme .cfg files present on the device.
    static func installedThemes(onVolume mount: String) -> [String] {
        let dir = mount + "/.rockbox/themes"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasSuffix(".cfg") }
            .map { String($0.dropLast(4)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Makes a theme active by folding its .cfg into the device's config.cfg.
    /// Rockbox reads config.cfg at boot, so the skin applies on next start.
    static func activateTheme(named theme: String, onVolume mount: String) throws {
        let themeCfgPath = "\(mount)/.rockbox/themes/\(theme).cfg"
        guard let themeCfg = try? String(contentsOfFile: themeCfgPath, encoding: .utf8) else {
            throw RockboxError.unzipFailed("theme \(theme) isn't on the device")
        }

        let configPath = "\(mount)/.rockbox/config.cfg"
        var config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""

        // Keys the theme owns; drop existing ones so the new theme wins.
        var themeKeys = Set<String>()
        var themeLines: [String] = []
        for line in themeCfg.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let colon = trimmed.firstIndex(of: ":") else { continue }
            themeKeys.insert(String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces))
            themeLines.append(trimmed)
        }

        var kept: [String] = []
        for line in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Drop the marker from a previous switch, or they stack up and the
            // first (stale) one wins when we read the active theme back.
            if trimmed.hasPrefix(themeMarkerPrefix) { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                if themeKeys.contains(key) { continue }
            }
            if !trimmed.isEmpty { kept.append(trimmed) }
        }

        config = (kept + ["", "\(themeMarkerPrefix) \(theme) \(themeMarkerSuffix)"] + themeLines)
            .joined(separator: "\n") + "\n"
        try config.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    private static let themeMarkerPrefix = "# theme:"
    private static let themeMarkerSuffix = "(set by iPod Connect)"

    /// The theme currently named in config.cfg, if iPod Connect set it.
    static func activeTheme(onVolume mount: String) -> String? {
        guard let config = try? String(contentsOfFile: "\(mount)/.rockbox/config.cfg", encoding: .utf8)
        else { return nil }
        // Read the last marker, so a file written by an older build that
        // accumulated markers still reports the most recent theme.
        for line in config.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(themeMarkerPrefix) else { continue }
            return trimmed
                .replacingOccurrences(of: themeMarkerPrefix, with: "")
                .replacingOccurrences(of: themeMarkerSuffix, with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: Bootloader (requires administrator rights)

    static var patcherURL: URL? {
        Bundle.main.url(forResource: "ipodpatcher", withExtension: nil)
    }

    /// Runs ipodpatcher as root via the standard macOS authorisation prompt.
    /// Returns its combined output.
    @discardableResult
    static func runPatcherAsAdmin(arguments: [String]) throws -> String {
        guard let patcher = patcherURL else { throw RockboxError.patcherMissing }

        let command = ([patcher.path] + arguments)
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let script = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: out, encoding: .utf8) ?? ""
        let errorOutput = String(data: err, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if errorOutput.contains("User canceled") || errorOutput.contains("-128") {
                throw RockboxError.cancelled
            }
            throw RockboxError.patcherFailed(
                errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? output : errorOutput)
        }
        return output
    }

    /// Read-only identification of attached iPods. Still needs root, because
    /// even reading the partition table requires raw disk access.
    static func scanDevices() throws -> String {
        try runPatcherAsAdmin(arguments: ["--scan"])
    }

    /// Where firmware backups are kept, so a bad flash can be reverted.
    static var backupDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPod Connect/Firmware Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Backs up the firmware partition, then writes the bootloader. The backup
    /// is not optional — it is the only way back if the flash goes wrong.
    static func installBootloader(device: String, bootloader: URL, deviceLabel: String) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = backupDirectory
            .appendingPathComponent("\(deviceLabel)-\(stamp).bin")

        try runPatcherAsAdmin(arguments: [device, "-r", backup.path])
        guard FileManager.default.fileExists(atPath: backup.path) else {
            throw RockboxError.patcherFailed("Firmware backup failed — refusing to write the bootloader.")
        }
        try runPatcherAsAdmin(arguments: [device, "-a", bootloader.path])
        return backup
    }

    static func removeBootloader(device: String) throws {
        try runPatcherAsAdmin(arguments: [device, "-d"])
    }

    // MARK: - iPod Classic 6G/7G (USB DFU)
    //
    // The Classic doesn't take a firmware-partition write like the older
    // iPods; its bootloader goes over USB while the device sits in DFU mode.
    // mks5lboot talks to it through IOKit, so unlike ipodpatcher this needs
    // neither libusb nor an administrator password.

    static var dfuToolURL: URL? {
        Bundle.main.url(forResource: "mks5lboot", withExtension: nil)
    }

    @discardableResult
    static func runDFUTool(_ arguments: [String]) throws -> (status: Int32, output: String) {
        guard let tool = dfuToolURL else { throw RockboxError.patcherMissing }
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// True once the iPod has appeared on USB in DFU mode.
    static func isIPodInDFUMode() -> Bool {
        guard let result = try? runDFUTool(["--dfuscan"]) else { return false }
        // The tool prints "no DFU devices found" when nothing is attached.
        return !result.output.localizedCaseInsensitiveContains("no DFU devices found")
            && !result.output.localizedCaseInsensitiveContains("DFU device not found")
    }

    /// Writes the bootloader to a Classic already sitting in DFU mode.
    static func installClassicBootloader(bootloader: URL) throws {
        let result = try runDFUTool(["--bl-inst", bootloader.path])
        let ok = result.status == 0
            && !result.output.localizedCaseInsensitiveContains("[ERR]")
        guard ok else {
            throw RockboxError.patcherFailed(
                result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
