import Foundation

/// Talks to rockbox.org: the theme catalogue and the firmware builds.
enum RockboxCatalog {
    static let themesBase = "https://themes.rockbox.org"
    static let downloadBase = "https://download.rockbox.org"
    static let release = "4.0"

    /// themes.rockbox.org sits behind an anti-bot filter that challenges
    /// browser-like user agents. Rockbox Utility's own agent is allowed
    /// through, so identify honestly as a tool rather than as a browser.
    static let userAgent = "iPodConnect/1.0 (Rockbox installer; +https://github.com/davidsomper/ipod-connect)"

    private static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }

    // MARK: Themes

    static func themesURL(for target: RockboxTarget) -> URL? {
        var components = URLComponents(string: "\(themesBase)/rbutilqt.php")
        components?.queryItems = [
            .init(name: "target", value: target.id),
            .init(name: "release", value: release),
            .init(name: "revision", value: ""),
            .init(name: "rbutilver", value: "1.5.1"),
        ]
        return components?.url
    }

    static func fetchThemes(for target: RockboxTarget) async throws -> [RockboxTheme] {
        guard let url = themesURL(for: target) else { throw RockboxError.badURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RockboxError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw RockboxError.badResponse
        }
        // An anti-bot challenge comes back as HTML with a 200.
        if text.hasPrefix("<") || text.localizedCaseInsensitiveContains("not a bot") {
            throw RockboxError.blocked
        }
        return parseThemes(text)
    }

    /// The catalogue is an INI document: one section per theme, plus
    /// `[error]` and `[status]` sections that we skip.
    static func parseThemes(_ text: String) -> [RockboxTheme] {
        var themes: [RockboxTheme] = []
        var section: String?
        var fields: [String: String] = [:]

        func flush() {
            guard let id = section, id != "error", id != "status",
                  let archive = fields["archive"], !archive.isEmpty else { return }
            themes.append(RockboxTheme(
                id: id,
                name: fields["name"] ?? id,
                author: fields["author"] ?? "Unknown",
                version: fields["version"] ?? "",
                about: decodeEntities(fields["about"] ?? ""),
                sizeBytes: Int(fields["size"] ?? "") ?? 0,
                previewPath: fields["image"].flatMap { $0.isEmpty ? nil : $0 },
                archivePath: archive
            ))
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                section = String(line.dropFirst().dropLast())
                fields = [:]
            } else if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                fields[key] = value
            }
        }
        flush()
        return themes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: Firmware & bootloader

    static func buildURL(for target: RockboxTarget) -> URL? {
        URL(string: "\(downloadBase)/release/\(release)/rockbox-\(target.id)-\(release).zip")
    }

    static func bootloaderURL(for target: RockboxTarget) -> URL? {
        guard target.bootloader == .ipodpatcher else { return nil }
        return URL(string: "\(downloadBase)/bootloader/ipod/bootloader-\(target.id).ipod")
    }

    /// Downloads to a temporary file, reporting 0…1 progress.
    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RockboxError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let total = http.expectedContentLength
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)

        var data = Data()
        if total > 0 { data.reserveCapacity(Int(total)) }
        var counter = 0
        for try await byte in bytes {
            data.append(byte)
            counter += 1
            if total > 0, counter % 65536 == 0 {
                progress(Double(counter) / Double(total))
            }
        }
        progress(1)
        try data.write(to: destination)
        return destination
    }

    static func fetchPreview(_ url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

enum RockboxError: LocalizedError {
    case badURL
    case badResponse
    case blocked
    case server(Int)
    case noDevice
    case notRockboxed
    case unzipFailed(String)
    case patcherMissing
    case patcherFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badURL: return "Couldn't build the request URL."
        case .badResponse: return "The server sent something unreadable."
        case .blocked: return "themes.rockbox.org blocked the request. Try again in a moment."
        case .server(let code): return "The server returned HTTP \(code)."
        case .noDevice: return "No iPod is connected."
        case .notRockboxed: return "Install Rockbox on this iPod first."
        case .unzipFailed(let detail): return "Couldn't unpack the archive: \(detail)"
        case .patcherMissing: return "The bootloader tool is missing from the app bundle."
        case .patcherFailed(let detail): return detail
        case .cancelled: return "Cancelled."
        }
    }
}
