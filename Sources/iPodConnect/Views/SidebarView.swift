import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @EnvironmentObject var rockbox: RockboxManager
    @State private var artwork: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("LIBRARY", isFirst: true)

            sourceRow("Music", icon: "music.note", source: .music)
            sourceRow("Artists", icon: "music.mic", source: .artists)
            sourceRow("Albums", icon: "square.stack", source: .albums)

            if let ipod = rockbox.selectedDevice {
                sectionHeader("DEVICE")
                sourceRow(ipod.volumeName, icon: "ipod", source: .device)
            }

            sectionHeader("ROCKBOX")
            sourceRow("Rockbox", icon: "gearshape.2", source: .rockbox)

            Spacer()

            NowPlayingArtView(artwork: $artwork)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBG)
        .overlay(alignment: .trailing) { Theme.sidebarBorder.frame(width: 1) }
        .task(id: "\(player.current?.id ?? "")#\(library.artworkVersion)") {
            artwork = nil
            guard let track = player.current else { return }
            let image = await ArtworkLoader.shared.artwork(for: track)
            if player.current == track { artwork = image }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Theme.sidebarHeaderText)
            .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
            .padding(.leading, 12)
            .padding(.top, isFirst ? 12 : 14)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sourceRow(_ label: String, icon: String, source: LibrarySource) -> some View {
        let isSelected = library.source == source
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.sidebarIcon)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.sidebarText)
                .shadow(color: isSelected ? .black.opacity(0.3) : .clear, radius: 0, y: -1)
            Spacer()
        }
        .padding(.leading, 16)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                Theme.sidebarSelGradient
                    .overlay(alignment: .top) { Color.white.opacity(0.25).frame(height: 1) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { library.source = source }
    }
}

/// The classic album-art panel pinned to the bottom of the source list.
struct NowPlayingArtView: View {
    @EnvironmentObject var player: Player
    @Binding var artwork: NSImage?

    var body: some View {
        if player.current != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Now Playing")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.sidebarHeaderText)
                    .padding(.leading, 2)

                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Theme.artPlaceholder
                            Image(systemName: "music.note")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.artGlyph)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .border(Theme.artBorder, width: 1)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .padding(10)
        }
    }
}
