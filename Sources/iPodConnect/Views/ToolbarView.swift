import SwiftUI
import AppKit

/// Transparent layer that makes the toolbar behave like a title bar:
/// drag to move the window, double-click to zoom (or minimize, matching
/// the "Double-click a window's title bar to…" System Setting).
struct TitleBarBehavior: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ToolbarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 14) {
            // Room for the traffic lights
            Spacer().frame(width: 66)

            // Transport controls
            HStack(spacing: 10) {
                TransportButton(systemName: "backward.fill", size: 28) { player.previous() }
                TransportButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", size: 38) {
                    player.togglePlayPause()
                }
                TransportButton(systemName: "forward.fill", size: 28) { player.next() }
            }

            // Volume
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.iconTint)
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.mini)
                    .tint(Theme.sliderTint)
                    .frame(width: 76)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.iconTint)
            }

            Spacer(minLength: 8)

            LCDView()
                .frame(maxWidth: 440)
                .frame(height: 46)

            Spacer(minLength: 8)

            if library.source == .music {
                ViewModeSwitcher()
            }

            SearchField()
                .frame(width: 170)

            Spacer().frame(width: 6)
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(TitleBarBehavior())
        .background(Theme.toolbarGradient)
        .overlay(alignment: .bottom) {
            Theme.toolbarBorder.frame(height: 1)
        }
    }
}

struct LCDView: View {
    @EnvironmentObject var player: Player

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.lcdGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.lcdBorder, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // Inner shadow hint at the top, like the recessed iTunes LCD
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color.black.opacity(0.12), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .frame(height: 7)
                        .padding(.horizontal, 1)
                        .padding(.top, 1)
                }

            if let track = player.current {
                VStack(spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.lcdText)
                        .lineLimit(1)
                    Text(subtitle(track))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.lcdSubText)
                        .lineLimit(1)
                    ProgressRow()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.lcdSubText)
                    Text("iPod Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.lcdSubText)
                }
            }
        }
    }

    private func subtitle(_ track: Track) -> String {
        let parts = [track.artist, track.album].filter { !$0.isEmpty }
        return parts.joined(separator: " — ")
    }
}

struct ProgressRow: View {
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 6) {
            Text(timeString(player.elapsed))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.lcdSubText)
                .frame(width: 34, alignment: .trailing)

            GeometryReader { geo in
                let fraction = player.duration > 0 ? min(1, player.elapsed / player.duration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.lcdProgressTrack).frame(height: 4)
                    Capsule().fill(Theme.lcdProgressFill)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                    // Diamond-ish scrubber knob
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.lcdKnob)
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(45))
                        .offset(x: max(0, geo.size.width * fraction - 4))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            player.seek(to: fraction * player.duration)
                        }
                )
            }
            .frame(height: 10)

            Text("-" + timeString(max(0, player.duration - player.elapsed)))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.lcdSubText)
                .frame(width: 38, alignment: .leading)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// The iTunes view switcher: list vs. Cover Flow, as a small capsule of
/// glossy segments.
struct ViewModeSwitcher: View {
    @EnvironmentObject var library: Library

    var body: some View {
        HStack(spacing: 0) {
            segment(icon: "list.bullet", mode: .list, help: "Song list")
            Theme.segmentBorder.frame(width: 1)
            segment(icon: "square.stack.3d.down.right.fill", mode: .coverFlow, help: "Cover Flow")
        }
        .frame(height: 21)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [Theme.segmentTop, Theme.segmentBottom],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.segmentBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }

    @ViewBuilder
    private func segment(icon: String, mode: MusicViewMode, help: String) -> some View {
        let isActive = library.musicViewMode == mode
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isActive ? .white : Theme.segmentGlyph)
            .frame(width: 30, height: 21)
            .background {
                if isActive {
                    LinearGradient(
                        colors: [Theme.segmentActiveTop, Theme.segmentActiveBottom],
                        startPoint: .top, endPoint: .bottom)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { library.musicViewMode = mode }
            .help(help)
    }
}

struct SearchField: View {
    @EnvironmentObject var library: Library
    @FocusState private var isFocused: Bool

    private var searchPlaceholder: String {
        switch library.source {
        case .music: return "Search"
        case .artists: return "Find in Artists"
        case .albums: return "Find in Albums"
        case .rockbox, .device: return "Search"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.iconTint)
            TextField(searchPlaceholder, text: $library.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.listText)
                .focused($isFocused)
                .onChange(of: library.focusSearchToken) { _ in
                    isFocused = true   // ⌘F
                }
            if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 21)
        .background(
            Capsule()
                .fill(Theme.fieldBG)
                .overlay(Capsule().strokeBorder(Theme.fieldBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        )
    }
}
