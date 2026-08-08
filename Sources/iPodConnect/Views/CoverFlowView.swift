import SwiftUI

/// Cover Flow: a 3D album carousel over the track listing for the centered
/// album, as in iTunes 7–10.
struct CoverFlowView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @State private var index = 0
    @State private var selectedTrackID: String?
    /// Set when the index change originated from a list click, so the list
    /// doesn't yank itself to the top of the album under the user's cursor.
    @State private var indexDrivenByList = false
    /// Drives the knob's lift-and-brighten while the user is scrubbing.
    @State private var isScrubbing = false

    private var albums: [AlbumGroup] { library.visibleAlbums }

    /// Every song, ordered by album so the list and the covers line up —
    /// nothing is hidden.
    private var tracks: [Track] { albums.flatMap(\.tracks) }

    var body: some View {
        VSplitView {
            carousel
                .frame(minHeight: 200, idealHeight: 300)
            trackList
                .frame(minHeight: 120)
        }
        .background(Theme.contentBG)
        .onChange(of: albums.count) { _, count in
            index = min(index, max(0, count - 1))
        }
    }

    private func albumIndex(for track: Track) -> Int? {
        albums.firstIndex { $0.tracks.contains(track) }
    }

    // MARK: Carousel

    private var carousel: some View {
        GeometryReader { geo in
            let coverSize = min(geo.size.height * 0.62, geo.size.width * 0.34)
            ZStack {
                LinearGradient(
                    colors: [Theme.coverFlowTop, Theme.coverFlowBottom],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                if albums.isEmpty {
                    Text("No albums")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ZStack {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                            let offset = i - index
                            if abs(offset) <= 5 {
                                CoverFlowCard(album: album, size: coverSize)
                                    .rotation3DEffect(
                                        .degrees(offset == 0 ? 0 : (offset < 0 ? 58 : -58)),
                                        axis: (x: 0, y: 1, z: 0),
                                        anchor: offset == 0 ? .center : (offset < 0 ? .trailing : .leading),
                                        perspective: 0.55
                                    )
                                    .scaleEffect(offset == 0 ? 1.0 : 0.82)
                                    .offset(x: xOffset(for: offset, coverSize: coverSize))
                                    .zIndex(Double(10 - abs(offset)))
                                    .onTapGesture {
                                        if offset == 0 { playAlbum(album) }
                                        else { withAnimation(.easeOut(duration: 0.28)) { index = i } }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.28), value: index)

                    VStack {
                        Spacer()
                        albumCaption
                        scrollBar
                            .padding(.horizontal, 40)
                            .padding(.bottom, 10)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        let steps = Int((-value.translation.width / 60).rounded())
                        move(by: steps == 0 ? (value.translation.width < 0 ? 1 : -1) : steps)
                    }
            )
            .background(CoverFlowScrollCatcher { delta in move(by: delta) })
        }
    }

    /// Centre cover sits alone; the rest fan out to either side, tightening
    /// as they recede.
    private func xOffset(for offset: Int, coverSize: CGFloat) -> CGFloat {
        guard offset != 0 else { return 0 }
        let direction: CGFloat = offset < 0 ? -1 : 1
        let depth = CGFloat(abs(offset))
        return direction * (coverSize * 0.52 + (depth - 1) * coverSize * 0.20)
    }

    @ViewBuilder
    private var albumCaption: some View {
        if albums.indices.contains(index) {
            let album = albums[index]
            VStack(spacing: 1) {
                Text(album.album)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.coverFlowText)
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.coverFlowSubText)
            }
            .lineLimit(1)
            .padding(.bottom, 6)
        }
    }

    private var scrollBar: some View {
        GeometryReader { geo in
            let count = max(albums.count - 1, 1)
            let fraction = CGFloat(index) / CGFloat(count)
            let knobWidth: CGFloat = 54
            let travel = max(0, geo.size.width - knobWidth)

            ZStack(alignment: .leading) {
                GlassTrack()
                    .frame(height: 11)
                GlassKnob(isDragging: isScrubbing)
                    .frame(width: knobWidth, height: 17)
                    .offset(x: fraction * travel)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isScrubbing = true
                            }
                        }
                        let usable = max(1, travel)
                        let f = max(0, min(1, (value.location.x - knobWidth / 2) / usable))
                        index = Int((f * CGFloat(count)).rounded())
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isScrubbing = false
                        }
                    }
            )
        }
        .frame(height: 20)
    }

    private func move(by steps: Int) {
        guard !albums.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            index = max(0, min(albums.count - 1, index + steps))
        }
    }

    // MARK: Full track list, kept in sync with the carousel

    private var trackList: some View {
        VStack(spacing: 0) {
            CoverFlowListHeader()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                            CoverFlowRow(
                                track: track,
                                number: track.trackNumber > 0 ? track.trackNumber : i + 1,
                                isSelected: selectedTrackID == track.id,
                                isPlaying: player.current == track,
                                isAlternate: !i.isMultiple(of: 2)
                            )
                            .id(track.id)
                            .onTapGesture(count: 2) {
                                select(track)
                                player.play(track: track, in: tracks)
                            }
                            .simultaneousGesture(TapGesture().onEnded { select(track) })
                        }
                    }
                }
                .background(Theme.contentBG)
                .onChange(of: index) { _, newIndex in
                    // Carousel moved on its own — bring the list along.
                    guard !indexDrivenByList else {
                        indexDrivenByList = false
                        return
                    }
                    guard albums.indices.contains(newIndex),
                          let first = albums[newIndex].tracks.first else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    /// Selecting a song flips the carousel to that song's album.
    private func select(_ track: Track) {
        selectedTrackID = track.id
        guard let target = albumIndex(for: track), target != index else { return }
        indexDrivenByList = true
        withAnimation(.easeOut(duration: 0.28)) { index = target }
    }

    private func playAlbum(_ album: AlbumGroup) {
        guard let first = album.tracks.first else { return }
        player.play(track: first, in: albums.flatMap(\.tracks))
    }
}

// MARK: - Liquid Glass slider
//
// Both pieces use the genuine system material through `NSGlassEffectView`
// (see LiquidGlass.swift) rather than a gradient imitation, so they refract
// the album art behind them exactly like the volume slider and other macOS 26
// glass controls.

/// The recessed channel the knob travels in — `clear` style, so it reads as
/// a subtle groove rather than a solid bar.
struct GlassTrack: View {
    var body: some View {
        Color.clear
            .liquidGlass(cornerRadius: 5.5, clear: true)
    }
}

/// The draggable pill. The system supplies the refraction and specular edge;
/// the tint and lift are ours, so it responds while scrubbing.
struct GlassKnob: View {
    let isDragging: Bool

    var body: some View {
        Color.clear
            .liquidGlass(
                cornerRadius: 8.5,
                tint: NSColor.white.withAlphaComponent(isDragging ? 0.22 : 0.10)
            )
            .shadow(color: .black.opacity(isDragging ? 0.34 : 0.20),
                    radius: isDragging ? 6 : 3,
                    y: isDragging ? 3 : 1.5)
            .scaleEffect(isDragging ? 1.06 : 1, anchor: .center)
    }
}

/// One cover plus its mirrored reflection.
struct CoverFlowCard: View {
    @EnvironmentObject var library: Library
    let album: AlbumGroup
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .frame(width: size, height: size)
                .clipped()
                .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)

            artwork
                .frame(width: size, height: size)
                .clipped()
                .scaleEffect(y: -1)
                .mask(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(height: size * 0.45, alignment: .top)
                .clipped()
        }
        .task(id: "\(album.id)#\(library.artworkVersion)") {
            guard let track = album.tracks.first else { return }
            image = await ArtworkLoader.shared.artwork(for: track)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x5A6070), Color(hex: 0x3A3F4C)],
                    startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

enum CoverFlowColumns {
    static let number: CGFloat = 34
    static let time: CGFloat = 52
    static let artist: CGFloat = 150
    static let album: CGFloat = 150
    static let kind: CGFloat = 56
}

struct CoverFlowListHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .padding(.leading, CoverFlowColumns.number + 6)
            Spacer(minLength: 8)
            Text("Time").frame(width: CoverFlowColumns.time, alignment: .leading)
            Text("Artist").frame(width: CoverFlowColumns.artist, alignment: .leading)
            Text("Album").frame(width: CoverFlowColumns.album, alignment: .leading)
            Text("Kind").frame(width: CoverFlowColumns.kind, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.headerText)
        .frame(height: 19)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }
}

struct CoverFlowRow: View {
    let track: Track
    let number: Int
    let isSelected: Bool
    let isPlaying: Bool
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white : Theme.nowPlayingIcon)
                } else {
                    Text("\(number)")
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                }
            }
            .frame(width: CoverFlowColumns.number, alignment: .trailing)
            .padding(.trailing, 6)

            Text(track.title)
                .foregroundStyle(isSelected ? .white : Theme.listText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(track.timeString)
                .monospacedDigit()
                .frame(width: CoverFlowColumns.time, alignment: .leading)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
            Text(track.artist)
                .lineLimit(1)
                .frame(width: CoverFlowColumns.artist, alignment: .leading)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
            Text(track.album)
                .lineLimit(1)
                .frame(width: CoverFlowColumns.album, alignment: .leading)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
            Text(track.format)
                .frame(width: CoverFlowColumns.kind, alignment: .leading)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
        }
        .font(.system(size: 11))
        .frame(height: 20)
        .background(
            isSelected
                ? AnyView(Theme.rowSelGradient)
                : AnyView(isAlternate ? Theme.rowAlt : Theme.contentBG)
        )
        .contentShape(Rectangle())
    }
}

/// Routes native two-finger trackpad scrolling over the carousel into cover
/// steps. Uses a local event monitor (rather than `scrollWheel(with:)`) because
/// a SwiftUI `.background` view never becomes the scroll event's target.
struct CoverFlowScrollCatcher: NSViewRepresentable {
    let onScroll: (Int) -> Void

    final class CatcherView: NSView {
        var onScroll: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }

                    // Only claim scrolls that happen over the carousel itself,
                    // so the track list below still scrolls normally.
                    let localPoint = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(localPoint) else { return event }

                    // A horizontal swipe wins; otherwise vertical also flips covers.
                    let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    var delta = horizontal ? -event.scrollingDeltaX : -event.scrollingDeltaY
                    if !event.hasPreciseScrollingDeltas { delta *= 10 }

                    self.accumulated += delta
                    let threshold: CGFloat = 26
                    while self.accumulated >= threshold {
                        self.accumulated -= threshold
                        self.onScroll?(1)
                    }
                    while self.accumulated <= -threshold {
                        self.accumulated += threshold
                        self.onScroll?(-1)
                    }
                    return nil
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
    }
}
