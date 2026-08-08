import SwiftUI

/// Artist browsing: a column-browser style artist list (classic iTunes) with
/// album-list detail — cover art, album info and a track table per album.
struct ArtistsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 0) {
            ArtistColumn()
                .frame(width: 210)
            Theme.headerBorder.frame(width: 1)
            AlbumListView()
        }
        .background(Theme.contentBG)
    }
}

struct ArtistColumn: View {
    @EnvironmentObject var library: Library

    var body: some View {
        VStack(spacing: 0) {
            Text("Artists")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.headerText)
                .frame(maxWidth: .infinity)
                .frame(height: 19)
                .background(Theme.headerGradient)
                .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    artistRow(name: "All Artists", value: nil, bold: true)
                    ForEach(library.visibleArtists, id: \.self) { artist in
                        artistRow(name: artist, value: artist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func artistRow(name: String, value: String?, bold: Bool = false) -> some View {
        let isSelected = library.selectedArtist == value
        HStack {
            Text(name)
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.listText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .frame(height: 20)
        .background(isSelected ? AnyView(Theme.rowSelGradient) : AnyView(Theme.contentBG))
        .contentShape(Rectangle())
        .onTapGesture { library.selectedArtist = value }
    }
}

struct AlbumListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @State private var selectedTrackID: String?

    var body: some View {
        let albums = library.albumGroups(for: library.selectedArtist)
        let queue = albums.flatMap(\.tracks)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(albums) { album in
                    AlbumSection(
                        album: album,
                        showArtist: library.selectedArtist == nil,
                        selectedTrackID: $selectedTrackID
                    ) { track in
                        player.play(track: track, in: queue)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.contentBG)
    }
}

struct AlbumSection: View {
    @EnvironmentObject var player: Player
    let album: AlbumGroup
    let showArtist: Bool
    @Binding var selectedTrackID: String?
    let playAction: (Track) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AlbumArtView(track: album.tracks.first)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.album)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                if showArtist {
                    Text(album.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(albumInfo)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        AlbumTrackRow(
                            track: track,
                            fallbackNumber: index + 1,
                            showTrackArtist: track.artist != album.artist && !track.artist.isEmpty,
                            isSelected: selectedTrackID == track.id,
                            isPlaying: player.current == track,
                            isAlternate: !index.isMultiple(of: 2)
                        )
                        .onTapGesture(count: 2) {
                            selectedTrackID = track.id
                            playAction(track)
                        }
                        .simultaneousGesture(TapGesture().onEnded { selectedTrackID = track.id })
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var albumInfo: String {
        var parts: [String] = []
        if !album.genre.isEmpty { parts.append(album.genre) }
        if !album.year.isEmpty { parts.append(album.year) }
        let minutes = Int(album.duration / 60)
        parts.append("\(album.tracks.count) songs, \(minutes) minutes")
        return parts.joined(separator: " · ")
    }
}

struct AlbumTrackRow: View {
    let track: Track
    let fallbackNumber: Int
    let showTrackArtist: Bool
    let isSelected: Bool
    let isPlaying: Bool
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white : Theme.nowPlayingIcon)
                } else {
                    Text("\(track.trackNumber > 0 ? track.trackNumber : fallbackNumber)")
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                }
            }
            .frame(width: 24, alignment: .trailing)

            Text(track.title)
                .foregroundStyle(isSelected ? .white : Theme.listText)
                .lineLimit(1)

            if showTrackArtist {
                Text(track.artist)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : Theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(track.timeString)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(
            isSelected
                ? AnyView(Theme.rowSelGradient)
                : AnyView(isAlternate ? Theme.rowAlt : Theme.contentBG)
        )
        .contentShape(Rectangle())
    }
}

struct AlbumArtView: View {
    @EnvironmentObject var library: Library
    let track: Track?
    var size: CGFloat = 110
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.artPlaceholder
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.27))
                        .foregroundStyle(Theme.artGlyph)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .border(Theme.artBorder, width: 1)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .task(id: "\(track?.id ?? "")#\(library.artworkVersion)") {
            image = nil
            if let track {
                image = await ArtworkLoader.shared.artwork(for: track)
            }
        }
    }
}
