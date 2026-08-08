import SwiftUI

// MARK: - Proportions
//
// The iPod classic body is 103.5 × 61.8 mm (a 1.675 ratio), with a 4:3 screen.
// Everything below is that geometry scaled to points.

enum IPodMetrics {
    static let bodyWidth: CGFloat = 380
    static let bodyHeight: CGFloat = 636          // 380 × 1.675

    static let bezel: CGFloat = 7
    static let displayWidth: CGFloat = 300        // 4:3 LCD
    static let displayHeight: CGFloat = 225
    static var screenWidth: CGFloat { displayWidth + bezel * 2 }
    static var screenHeight: CGFloat { displayHeight + bezel * 2 }

    static let wheelDiameter: CGFloat = 264
    static let topInset: CGFloat = 43
    static let screenToWheel: CGFloat = 30

    static var bodySize: NSSize { NSSize(width: bodyWidth, height: bodyHeight) }
}

// MARK: - Screen model

enum IPodScreen: Equatable {
    case mainMenu, musicMenu
    case artists, artistSongs(String)
    case albums, albumSongs(String, String)
    case songs
    case extras, clock, settings, about
    case message(String, String)   // title, body text
    case nowPlaying
}

struct IPodScreenState: Equatable {
    var screen: IPodScreen
    var selection: Int = 0
}

struct IPodMenuRow {
    let title: String
    var value: String?
    var chevron = true
}

// MARK: - Trackpad / mouse scroll support

/// Routes native scroll-wheel (two-finger trackpad) events anywhere over the
/// iPod window into click-wheel scroll steps. Never intercepts clicks.
struct ScrollWheelCatcher: NSViewRepresentable {
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
                    var delta = event.scrollingDeltaY
                    if !event.hasPreciseScrollingDeltas { delta *= 12 }
                    self.accumulated += delta
                    let threshold: CGFloat = 22
                    while self.accumulated <= -threshold {
                        self.accumulated += threshold
                        self.onScroll?(1)
                    }
                    while self.accumulated >= threshold {
                        self.accumulated -= threshold
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

// MARK: - iPod body

struct IPodView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @State private var stack = [IPodScreenState(screen: .mainMenu)]
    @State private var previewArt: NSImage?
    @State private var previewIndex = 0

    private let artTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var current: IPodScreenState { stack[stack.count - 1] }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: IPodMetrics.topInset)

            IPodScreenChrome(
                title: title(for: current.screen),
                canGoBack: stack.count > 1,
                onBack: goBack
            ) {
                screenContent
            }
            .frame(width: IPodMetrics.screenWidth, height: IPodMetrics.screenHeight)

            Spacer().frame(height: IPodMetrics.screenToWheel)

            ClickWheelView(
                onMenu: goBack,
                onPrev: { player.previous() },
                onNext: { player.next() },
                onPlayPause: { player.togglePlayPause() },
                onSelect: { activate(index: current.selection) },
                onScroll: { delta in scroll(delta) }
            )
            .frame(width: IPodMetrics.wheelDiameter, height: IPodMetrics.wheelDiameter)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScrollWheelCatcher { delta in scroll(delta) })
        .background(TitleBarBehavior())
        .background(Theme.ipodBodyGradient)
        .overlay(alignment: .bottomTrailing) {
            Button {
                library.ipodMode = false
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.ipodWheelLabel)
            }
            .buttonStyle(.plain)
            .help("Return to classic view")
            .padding(10)
        }
        .task { await loadPreviewArt(advance: false) }
        .onReceive(artTimer) { _ in
            Task { await loadPreviewArt(advance: true) }
        }
        .onChange(of: player.current) { _, _ in
            Task { await loadPreviewArt(advance: false) }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch current.screen {
        case .nowPlaying:
            NowPlayingScreen()
        case .about:
            AboutScreen()
        case .clock:
            ClockScreen()
        case .message(_, let text):
            MessageScreen(text: text)
        default:
            MenuScreen(
                rows: rows(for: current.screen),
                selection: current.selection,
                splitPane: hasSplitPane(current.screen),
                previewArt: previewArt,
                onRowTap: { index in
                    stack[stack.count - 1].selection = index
                    activate(index: index)
                }
            )
        }
    }

    // MARK: Preview pane artwork

    private func loadPreviewArt(advance: Bool) async {
        if let track = player.current {
            previewArt = await ArtworkLoader.shared.artwork(for: track)
            return
        }
        let albums = library.allAlbums
        guard !albums.isEmpty else { previewArt = nil; return }
        if advance { previewIndex += 1 }
        for offset in 0..<albums.count {
            let album = albums[(previewIndex + offset) % albums.count]
            if let track = album.tracks.first,
               let image = await ArtworkLoader.shared.artwork(for: track) {
                previewIndex = (previewIndex + offset) % albums.count
                previewArt = image
                return
            }
        }
        previewArt = nil
    }

    // MARK: Screen data

    private func title(for screen: IPodScreen) -> String {
        switch screen {
        case .mainMenu: return "iPod"
        case .musicMenu: return "Music"
        case .artists: return "Artists"
        case .artistSongs(let artist): return artist
        case .albums: return "Albums"
        case .albumSongs(_, let album): return album
        case .songs: return "Songs"
        case .extras: return "Extras"
        case .clock: return "Clock"
        case .settings: return "Settings"
        case .about: return "About"
        case .message(let title, _): return title
        case .nowPlaying: return "Now Playing"
        }
    }

    private func hasSplitPane(_ screen: IPodScreen) -> Bool {
        switch screen {
        case .mainMenu, .musicMenu, .extras, .settings: return true
        default: return false
        }
    }

    private func trackList(for screen: IPodScreen) -> [Track]? {
        switch screen {
        case .artistSongs(let artist):
            return library.albumGroups(for: artist).flatMap(\.tracks)
        case .albumSongs(let artist, let album):
            return library.albumGroups(for: artist).first { $0.album == album }?.tracks ?? []
        case .songs:
            return library.songsByTitle
        default:
            return nil
        }
    }

    private func rows(for screen: IPodScreen) -> [IPodMenuRow] {
        if let list = trackList(for: screen) {
            return list.map { IPodMenuRow(title: $0.title, chevron: false) }
        }
        switch screen {
        case .mainMenu:
            return [
                IPodMenuRow(title: "Music"),
                IPodMenuRow(title: "Photos"),
                IPodMenuRow(title: "Podcasts"),
                IPodMenuRow(title: "Extras"),
                IPodMenuRow(title: "Settings"),
                IPodMenuRow(title: "Shuffle Songs", chevron: false),
                IPodMenuRow(title: "Now Playing"),
            ]
        case .musicMenu:
            return [
                IPodMenuRow(title: "Artists"),
                IPodMenuRow(title: "Albums"),
                IPodMenuRow(title: "Songs"),
            ]
        case .artists:
            return library.allArtists.map { IPodMenuRow(title: $0) }
        case .albums:
            return library.allAlbums.map { IPodMenuRow(title: $0.album) }
        case .extras:
            return [IPodMenuRow(title: "Clock")]
        case .settings:
            return [
                IPodMenuRow(title: "About"),
                IPodMenuRow(title: "Shuffle", value: player.shuffle ? "Songs" : "Off", chevron: false),
                IPodMenuRow(title: "Repeat", value: repeatLabel, chevron: false),
            ]
        default:
            return []
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Off"
        case .one: return "One"
        case .all: return "All"
        }
    }

    // MARK: Navigation & actions

    private func push(_ screen: IPodScreen) {
        stack.append(IPodScreenState(screen: screen))
    }

    private func goBack() {
        if stack.count > 1 { stack.removeLast() }
    }

    private func scroll(_ delta: Int) {
        if current.screen == .nowPlaying {
            player.volume = min(1, max(0, player.volume + Double(delta) * 0.04))
            return
        }
        let count = rows(for: current.screen).count
        guard count > 0 else { return }
        stack[stack.count - 1].selection = max(0, min(count - 1, current.selection + delta))
    }

    private func activate(index: Int) {
        switch current.screen {
        case .mainMenu:
            switch index {
            case 0: push(.musicMenu)
            case 1: push(.message("Photos", "No Photos"))
            case 2: push(.message("Podcasts", "No Podcasts"))
            case 3: push(.extras)
            case 4: push(.settings)
            case 5:
                let all = library.songsByTitle
                guard let track = all.randomElement() else { return }
                player.shuffle = true
                player.play(track: track, in: all)
                push(.nowPlaying)
            case 6:
                if player.current != nil { push(.nowPlaying) }
            default: break
            }
        case .musicMenu:
            switch index {
            case 0: push(.artists)
            case 1: push(.albums)
            case 2: push(.songs)
            default: break
            }
        case .artists:
            let artists = library.allArtists
            guard index < artists.count else { return }
            push(.artistSongs(artists[index]))
        case .albums:
            let albums = library.allAlbums
            guard index < albums.count else { return }
            push(.albumSongs(albums[index].artist, albums[index].album))
        case .artistSongs, .albumSongs, .songs:
            guard let list = trackList(for: current.screen), index < list.count else { return }
            player.play(track: list[index], in: list)
            push(.nowPlaying)
        case .extras:
            if index == 0 { push(.clock) }
        case .settings:
            switch index {
            case 0: push(.about)
            case 1: player.shuffle.toggle()
            case 2:
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            default: break
            }
        default:
            break
        }
    }
}

// MARK: - Screen chrome (bezel + title bar)

struct IPodScreenChrome<Content: View>: View {
    @EnvironmentObject var player: Player
    let title: String
    let canGoBack: Bool
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(Color(hex: 0x3A3C3E), lineWidth: 1))
        .padding(IPodMetrics.bezel)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.ipodScreenBezel))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.ipodScreenEdge, lineWidth: 1))
    }

    private var titleBar: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFDFDFD), Color(hex: 0xCECECE)],
                startPoint: .top, endPoint: .bottom)
            HStack(spacing: 4) {
                if canGoBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x444444))
                    }
                    .buttonStyle(.plain)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Spacer()
                if player.isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: 0x3B8CE8))
                } else if player.current != nil {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: 0x777777))
                }
                Image(systemName: "battery.100percent")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x53B155))
            }
            .padding(.horizontal, 7)
        }
        .frame(height: 21)
        .overlay(alignment: .bottom) { Color(hex: 0x8F8F8F).frame(height: 1) }
    }
}

// MARK: - Menu screen (with optional split preview pane)

struct MenuScreen: View {
    let rows: [IPodMenuRow]
    let selection: Int
    let splitPane: Bool
    let previewArt: NSImage?
    let onRowTap: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                menuList
                    .frame(width: splitPane ? round(geo.size.width * 0.54) : geo.size.width)
                if splitPane {
                    Color(hex: 0x555555).frame(width: 1)
                    previewPane(
                        width: geo.size.width - round(geo.size.width * 0.54) - 1,
                        height: geo.size.height
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var menuList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        let isSelected = index == selection
                        HStack(spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .black)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if let value = row.value {
                                Text(value)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color(hex: 0x8A8A8A))
                            }
                            if isSelected && row.chevron {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 5)
                        .frame(height: 23)
                        .background(
                            isSelected
                                ? AnyView(LinearGradient(
                                    colors: [Color(hex: 0x55A5F5), Color(hex: 0x1B65CB)],
                                    startPoint: .top, endPoint: .bottom))
                                : AnyView(Color.white)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onRowTap(index) }
                        .id(index)
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                proxy.scrollTo(newValue)
            }
        }
    }

    /// Sized explicitly, then clipped last, so tall or wide covers can never
    /// bleed past the screen bezel.
    private func previewPane(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x51628A), Color(hex: 0x2A3A5C)],
                startPoint: .top, endPoint: .bottom)
            if let previewArt {
                Image(nsImage: previewArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: previewArt)
    }
}

// MARK: - Simple info screens

struct MessageScreen: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x888888))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ClockScreen: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Spacer()
                Text(context.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .foregroundStyle(.black)
                Text(context.date.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x777777))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct AboutScreen: View {
    @EnvironmentObject var library: Library

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("iPod Connect")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
            Text("Songs: \(library.tracks.count)")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x555555))
            Text("Library: \(ByteCountFormatter.string(fromByteCount: library.totalBytes, countStyle: .file))")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x555555))
            Text("Version 1.0")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x999999))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Now Playing screen

struct NowPlayingScreen: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @State private var artwork: NSImage?

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        if let artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Color(hex: 0xE8EAED)
                                Image(systemName: "music.note")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(hex: 0xADB4BC))
                            }
                        }
                    }
                    .frame(width: 62, height: 62)
                    .clipped()
                    .border(Color(hex: 0xC0C0C0), width: 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                        Text(track.album)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0x777777))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.top, 9)

                Spacer()

                // Progress bar (click/drag to seek)
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let fraction = player.duration > 0 ? min(1, player.elapsed / player.duration) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: 0xDCDCDC))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(Color(hex: 0xB8B8B8), lineWidth: 1)
                                )
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(
                                    colors: [Color(hex: 0x6FB1F5), Color(hex: 0x2268C8)],
                                    startPoint: .top, endPoint: .bottom))
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { value in
                                guard player.duration > 0 else { return }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                player.seek(to: fraction * player.duration)
                            }
                        )
                    }
                    .frame(height: 9)

                    HStack {
                        Text(timeString(player.elapsed))
                        Spacer()
                        Text("-" + timeString(max(0, player.duration - player.elapsed)))
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x666666))
                }
                .padding(.horizontal, 9)

                // Volume (scroll the wheel here to adjust)
                HStack(spacing: 5) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(hex: 0x888888))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0xE0E0E0))
                            Capsule().fill(Color(hex: 0x8F9296))
                                .frame(width: max(3, geo.size.width * player.volume))
                        }
                    }
                    .frame(height: 4)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(hex: 0x888888))
                }
                .padding(.horizontal, 9)
                .padding(.top, 5)
                .padding(.bottom, 8)
            }
            .task(id: "\(track.id)#\(library.artworkVersion)") {
                artwork = await ArtworkLoader.shared.artwork(for: track)
            }
        } else {
            MessageScreen(text: "Nothing Playing")
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Click wheel

struct ClickWheelView: View {
    let onMenu: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onPlayPause: () -> Void
    let onSelect: () -> Void
    let onScroll: (Int) -> Void

    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0
    @State private var moved = false

    private let labelColor = Theme.ipodWheelLabel

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let centerDiameter = size * 0.37

            ZStack {
                // White wheel, like the silver 6G classic
                Circle()
                    .fill(Theme.ipodWheelGradient)
                    .overlay(Circle().strokeBorder(Theme.ipodWheelBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)

                VStack {
                    Text("MENU")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(labelColor)
                    Spacer()
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                }
                .padding(.vertical, 15)

                HStack {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                    Spacer()
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                }
                .padding(.horizontal, 15)

                // Silver center button
                Circle()
                    .fill(Theme.ipodCenterGradient)
                    .overlay(Circle().strokeBorder(Theme.ipodCenterBorder, lineWidth: 1))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 2)
                            .blur(radius: 1)
                            .padding(1)
                    )
                    .frame(width: centerDiameter, height: centerDiameter)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleChanged(value, center: center, centerRadius: centerDiameter / 2)
                    }
                    .onEnded { value in
                        handleEnded(value, center: center, centerRadius: centerDiameter / 2)
                    }
            )
        }
    }

    private func handleChanged(_ value: DragGesture.Value, center: CGPoint, centerRadius: CGFloat) {
        if hypot(value.translation.width, value.translation.height) > 8 { moved = true }
        let dx = value.location.x - center.x
        let dy = value.location.y - center.y
        guard hypot(dx, dy) > centerRadius else {
            lastAngle = nil
            return
        }
        let angle = atan2(dy, dx) * 180 / .pi
        if let last = lastAngle {
            var delta = angle - last
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            accumulated += delta
            // Every ~14° of rotation is one scroll step; clockwise scrolls down.
            while accumulated >= 14 { accumulated -= 14; onScroll(1) }
            while accumulated <= -14 { accumulated += 14; onScroll(-1) }
        }
        lastAngle = angle
    }

    private func handleEnded(_ value: DragGesture.Value, center: CGPoint, centerRadius: CGFloat) {
        defer {
            lastAngle = nil
            accumulated = 0
            moved = false
        }
        guard !moved else { return }
        let dx = value.location.x - center.x
        let dy = value.location.y - center.y
        if hypot(dx, dy) <= centerRadius {
            onSelect()
            return
        }
        let angle = atan2(dy, dx) * 180 / .pi
        switch angle {
        case -135 ..< -45: onMenu()
        case -45 ..< 45: onNext()
        case 45 ..< 135: onPlayPause()
        default: onPrev()
        }
    }
}
