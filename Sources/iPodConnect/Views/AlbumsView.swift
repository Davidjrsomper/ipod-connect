import SwiftUI

/// Album browsing: the iTunes 10 grid view — a wall of covers with a hover
/// play button, drilling into a track listing on double-click.
struct AlbumsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @State private var selectedAlbumID: String?
    @State private var openAlbumID: String?

    private var albums: [AlbumGroup] { library.visibleAlbums }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let openAlbumID, let album = albums.first(where: { $0.id == openAlbumID }) {
                AlbumDetailView(album: album)
            } else {
                grid
            }
        }
        .background(Theme.contentBG)
        .onChange(of: library.searchText) { _ in
            // A filtered-away album shouldn't stay open.
            if let openAlbumID, !albums.contains(where: { $0.id == openAlbumID }) {
                self.openAlbumID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            if openAlbumID != nil {
                Button {
                    openAlbumID = nil
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Albums")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.headerText)
                }
                .buttonStyle(.plain)
            } else {
                Text("Albums")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.headerText)
            }
            Spacer()
            Text(albums.count == 1 ? "1 album" : "\(albums.count) albums")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 152), spacing: 20, alignment: .top)],
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(albums) { album in
                    AlbumCell(
                        album: album,
                        isSelected: selectedAlbumID == album.id,
                        onSelect: { selectedAlbumID = album.id },
                        onOpen: {
                            selectedAlbumID = album.id
                            openAlbumID = album.id
                        },
                        onPlay: { play(album) }
                    )
                }
            }
            .padding(18)
        }
    }

    private func play(_ album: AlbumGroup) {
        guard let first = album.tracks.first else { return }
        // Queue continues through the rest of the grid, as iTunes did.
        let queue = albums.flatMap(\.tracks)
        player.play(track: first, in: queue)
    }
}

struct AlbumCell: View {
    let album: AlbumGroup
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                AlbumArtView(track: album.tracks.first, size: 148)
                if isHovering {
                    Button(action: onPlay) {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.55))
                                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .transition(.opacity)
                    .help("Play album")
                }
            }
            .frame(width: 148, height: 148)

            Text(album.album)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.listText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)

            Text(album.artist)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                .lineLimit(1)
                .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .frame(width: 148, alignment: .leading)
        .padding(6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4).fill(Theme.rowSelGradient)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

/// One album opened from the grid: big cover, details, and its track table.
struct AlbumDetailView: View {
    @EnvironmentObject var player: Player
    let album: AlbumGroup
    @State private var selectedTrackID: String?

    var body: some View {
        ScrollView {
            AlbumSection(
                album: album,
                showArtist: true,
                selectedTrackID: $selectedTrackID
            ) { track in
                player.play(track: track, in: album.tracks)
            }
            .padding(18)
        }
    }
}
