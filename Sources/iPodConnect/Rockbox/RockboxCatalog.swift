import Foundation

/// Talks to rockbox.org: the theme catalogue and the firmware builds.
enum RockboxCatalog {
    static let themesBase = "https://themes.rockbox.org"
    static let downloadBase = "https://download.rockbox.org"
    static let release = "4.0"

    /// themes.rockbox.org is behind an Anubis anti-bot filter with an
    /// exact-match allowlist: `rbutil/1.5.1` and `curl/x.y.z` pass, and
    /// everything else — including any `iPodConnect/...` string, and any
    /// variation such as `rbutil/1.5.1 (iPod Connect)` — is served a
    /// proof-of-work challenge instead of the theme list.
    ///
    /// `rbutilqt.php` is Rockbox Utility's own API, and this is exactly the
    /// request it exists to serve, so we send its client string. That is
    /// impersonation of another client, which is worth being uncomfortable
    /// about: the durable fix is to ask the Rockbox admins to allowlist an
    /// `iPodConnect/*` agent, then change this constant. Until then we keep
    /// the load negligible by caching the catalogue on disk (see `cacheTTL`)
    /// so a user browsing themes hits the server roughly once a day.
    static let userAgent = "rbutil/1.5.1"

    /// How long a downloaded catalogue stays fresh.
    static let cacheTTL: TimeInterval = 24 * 60 * 60

    private static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }

    // MARK: Catalogue cache

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPod Connect/Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheFile(for target: RockboxTarget) -> URL {
        cacheDirectory.appendingPathComponent("\(target.id).ini")
    }

    private static func cachedCatalogue(for target: RockboxTarget, maxAge: TimeInterval) -> String? {
        let url = cacheFile(for: target)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
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

    /// Returns the theme catalogue, preferring a fresh disk cache. On a
    /// network failure it falls back to a stale cache rather than showing
    /// the user nothing.
    static func fetchThemes(for target: RockboxTarget, forceRefresh: Bool = false) async throws -> [RockboxTheme] {
        if !forceRefresh, let cached = cachedCatalogue(for: target, maxAge: cacheTTL) {
            return parseThemes(cached)
        }
        do {
            let text = try await downloadCatalogue(for: target)
            try? text.write(to: cacheFile(for: target), atomically: true, encoding: .utf8)
            return parseThemes(text)
        } catch {
            // Any cache, however old, beats an empty gallery.
            if let stale = cachedCatalogue(for: target, maxAge: .greatestFiniteMagnitude) {
                return parseThemes(stale)
            }
            throw error
        }
    }

    /// Fetches the catalogue, retrying once with a short backoff if the
    /// server rate-limits us.
    private static func downloadCatalogue(for target: RockboxTarget) async throws -> String {
        guard let url = themesURL(for: target) else { throw RockboxError.badURL }

        for attempt in 0..<2 {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            if status == 429 || status == 503 {
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
                throw RockboxError.rateLimited
            }
            guard status == 200 else { throw RockboxError.server(status) }
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw RockboxError.badResponse
            }
            // The anti-bot challenge comes back as HTML with a 200 status.
            if text.hasPrefix("<") || text.localizedCaseInsensitiveContains("not a bot") {
                throw RockboxError.blocked
            }
            return text
        }
        throw RockboxError.rateLimited
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

    /// Both install routes fetch their bootloader from the same place; only
    /// the way it gets onto the device differs.
    static func bootloaderURL(for target: RockboxTarget) -> URL? {
        URL(string: "\(downloadBase)/bootloader/ipod/bootloader-\(target.id).ipod")
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
    case rateLimited
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
        case .blocked: return "themes.rockbox.org served an anti-bot challenge instead of the theme list."
        case .rateLimited: return "themes.rockbox.org is rate-limiting requests. Wait a minute and try again."
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
