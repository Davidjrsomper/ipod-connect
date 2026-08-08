import SwiftUI
import UniformTypeIdentifiers

/// Lists albums (or individual songs) with no artwork and lets the user
/// supply an image for each. Images are stored alongside the library; the
/// music files themselves are never rewritten.
struct MissingArtworkView: View {
    enum Scope: String, CaseIterable {
        case albums = "Albums"
        case songs = "Songs"
    }

    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var scope: Scope = .albums
    @State private var missingAlbums: [AlbumGroup] = []
    @State private var missingTracks: [Track] = []
    @State private var isScanning = true
    @State private var resolved: [String: NSImage] = [:]   // key -> newly set image
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .background(Theme.contentBG)
        .task { await scan() }
        .onChange(of: scope) { _, _ in Task { await scan() } }
        .alert("Couldn't Add Artwork", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 8) {
            Text("Add Missing Album Art")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.emptyTitle)
            Text("Artwork embedded in your files is used automatically. Anything without art is listed here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)

            Picker("", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.headerGradient)
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking your library for missing artwork…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentIsEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.emptyGlyph)
                Text(scope == .albums
                     ? "Every album has artwork."
                     : "Every song has artwork.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if scope == .albums {
                        ForEach(Array(missingAlbums.enumerated()), id: \.element.id) { i, album in
                            row(
                                key: ArtworkStore.albumKey(artist: album.artist, album: album.album),
                                title: album.album,
                                subtitle: "\(album.artist) · \(album.tracks.count) songs",
                                paths: album.tracks.map(\.path),
                                isAlternate: !i.isMultiple(of: 2)
                            )
                        }
                    } else {
                        ForEach(Array(missingTracks.enumerated()), id: \.element.id) { i, track in
                            row(
                                key: ArtworkStore.trackKey(path: track.path),
                                title: track.title,
                                subtitle: "\(track.artist) · \(track.album)",
                                paths: [track.path],
                                isAlternate: !i.isMultiple(of: 2)
                            )
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(Theme.statusGradient)
    }

    private var currentIsEmpty: Bool {
        scope == .albums ? missingAlbums.isEmpty : missingTracks.isEmpty
    }

    private var statusText: String {
        let added = resolved.count
        let remaining = scope == .albums ? missingAlbums.count : missingTracks.count
        if added > 0 {
            return "\(added) added · \(remaining) still missing"
        }
        return remaining == 0 ? "Nothing missing" : "\(remaining) missing artwork"
    }

    // MARK: Rows

    @ViewBuilder
    private func row(key: String, title: String, subtitle: String, paths: [String], isAlternate: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = resolved[key] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.artPlaceholder
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.artGlyph)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
            .border(Theme.artBorder, width: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if resolved[key] != nil {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .labelStyle(.titleAndIcon)
            }

            Button(resolved[key] == nil ? "Choose Image…" : "Replace…") {
                chooseImage(key: key, paths: paths, title: title)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isAlternate ? Theme.rowAlt : Theme.contentBG)
    }

    private func chooseImage(key: String, paths: [String], title: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Image"
        panel.message = "Choose artwork for “\(title)”"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ArtworkStore.shared.setImage(from: url, forKey: key)
            ArtworkLoader.shared.invalidate(paths: paths)
            resolved[key] = ArtworkStore.shared.image(forKey: key)
            library.artworkVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Scanning

    private func scan() async {
        isScanning = true
        defer { isScanning = false }

        if scope == .albums {
            var result: [AlbumGroup] = []
            for album in library.allAlbums {
                guard let first = album.tracks.first else { continue }
                if await ArtworkLoader.shared.artwork(for: first) == nil {
                    result.append(album)
                }
            }
            missingAlbums = result
        } else {
            var result: [Track] = []
            for track in library.songsByTitle {
                if await ArtworkLoader.shared.artwork(for: track) == nil {
                    result.append(track)
                }
            }
            missingTracks = result
        }
    }
}
