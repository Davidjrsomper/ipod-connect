import SwiftUI

struct ColumnWidths {
    let number: CGFloat = 40
    let time: CGFloat = 56
    let kind: CGFloat = 58
    var name: CGFloat
    var artist: CGFloat
    var album: CGFloat
    var genre: CGFloat

    init(total: CGFloat) {
        let flexible = max(300, total - 40 - 56 - 58)
        name = flexible * 0.36
        artist = flexible * 0.25
        album = flexible * 0.25
        genre = flexible * 0.14
    }
}

struct TrackListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @FocusState private var listFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let widths = ColumnWidths(total: geo.size.width)
            let visible = library.visibleTracks
            VStack(spacing: 0) {
                HeaderRow(widths: widths)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, track in
                                TrackRow(
                                    track: track,
                                    index: index,
                                    widths: widths,
                                    isSelected: library.selectedTrackID == track.id,
                                    isPlaying: player.current == track
                                )
                                .id(track.id)
                                .onTapGesture(count: 2) {
                                    library.selectedTrackID = track.id
                                    listFocused = true
                                    player.play(track: track, in: visible)
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    library.selectedTrackID = track.id
                                    listFocused = true
                                })
                            }
                        }
                    }
                    .background(Theme.contentBG)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.space) {
                        player.togglePlayPause()
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let selected = library.selectedTrackID,
                           let track = visible.first(where: { $0.id == selected }) {
                            player.play(track: track, in: visible)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) { moveSelection(1, in: visible, proxy: proxy) }
                    .onKeyPress(.upArrow) { moveSelection(-1, in: visible, proxy: proxy) }
                    .onChange(of: library.goToCurrentToken) { _, _ in
                        // ⌘L — reveal the playing track and select it.
                        guard let playing = player.current else { return }
                        library.selectedTrackID = playing.id
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(playing.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func moveSelection(_ delta: Int, in visible: [Track], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !visible.isEmpty else { return .ignored }
        let currentIndex = library.selectedTrackID.flatMap { id in visible.firstIndex(where: { $0.id == id }) }
        let newIndex = max(0, min(visible.count - 1, (currentIndex ?? -1) + delta))
        library.selectedTrackID = visible[newIndex].id
        proxy.scrollTo(visible[newIndex].id)
        return .handled
    }
}

struct HeaderRow: View {
    @EnvironmentObject var library: Library
    let widths: ColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            headerCell("", field: nil, width: widths.number)
            headerCell("Name", field: .name, width: widths.name)
            headerCell("Time", field: .time, width: widths.time)
            headerCell("Artist", field: .artist, width: widths.artist)
            headerCell("Album", field: .album, width: widths.album)
            headerCell("Genre", field: .genre, width: widths.genre)
            headerCell("Kind", field: .kind, width: widths.kind)
            Spacer(minLength: 0)
        }
        .frame(height: 19)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }

    @ViewBuilder
    private func headerCell(_ label: String, field: SortField?, width: CGFloat) -> some View {
        let isActive = field != nil && library.sortField == field
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.headerText)
                .lineLimit(1)
            if isActive {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 6))
                    .rotationEffect(.degrees(library.sortAscending ? 0 : 180))
                    .foregroundStyle(Theme.headerSortArrow)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .frame(width: width, height: 19)
        .background(isActive ? AnyView(Theme.headerActiveGradient) : AnyView(Color.clear))
        .overlay(alignment: .trailing) { Theme.headerBorder.opacity(0.6).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            if let field { library.setSort(field) }
        }
    }
}

struct TrackRow: View {
    let track: Track
    let index: Int
    let widths: ColumnWidths
    let isSelected: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white : Theme.nowPlayingIcon)
                        .frame(width: widths.number, alignment: .trailing)
                        .padding(.trailing, 0)
                } else {
                    Text("\(index + 1)")
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                        .frame(width: widths.number, alignment: .trailing)
                }
            }
            .padding(.trailing, 4)

            cell(track.title, width: widths.name, bold: false)
            cell(track.timeString, width: widths.time, secondary: true)
            cell(track.artist, width: widths.artist)
            cell(track.album, width: widths.album)
            cell(track.genre, width: widths.genre)
            cell(track.format, width: widths.kind, secondary: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .frame(height: 20)
        .background(background)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cell(_ text: String, width: CGFloat, bold: Bool = false, secondary: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .foregroundStyle(isSelected ? .white : (secondary ? Theme.secondaryText : Theme.listText))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .frame(width: width, alignment: .leading)
    }

    private var background: some View {
        Group {
            if isSelected {
                Theme.rowSelGradient
            } else if index.isMultiple(of: 2) {
                Theme.contentBG
            } else {
                Theme.rowAlt
            }
        }
    }
}
