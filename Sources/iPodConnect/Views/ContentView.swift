import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @AppStorage("darkMode") private var darkMode = false
    @State private var savedFrame: NSRect?

    private static let classicMinSize = NSSize(width: 900, height: 540)

    var body: some View {
        Group {
            if library.ipodMode {
                IPodView()
            } else {
                VStack(spacing: 0) {
                    ToolbarView()
                    HSplitView {
                        SidebarView()
                            .frame(minWidth: 150, idealWidth: 185, maxWidth: 300)
                        mainArea
                            .frame(minWidth: 480, maxWidth: .infinity)
                    }
                    StatusBarView()
                }
                .frame(minWidth: 900, minHeight: 540)
            }
        }
        .background(WindowAccessor())
        .ignoresSafeArea(.all, edges: .top)
        .preferredColorScheme(darkMode ? .dark : .light)
        .sheet(isPresented: $library.showMissingArtwork) {
            MissingArtworkView()
                .environmentObject(library)
        }
        .onChange(of: library.ipodMode) { _, ipod in
            morphWindow(toIPod: ipod)
        }
        .onAppear { applyAppearance() }
        .onChange(of: darkMode) { _, _ in applyAppearance() }
    }

    /// Sets the appearance app-wide so menus, panels and the traffic lights
    /// match the window, and the dynamic Theme colors resolve correctly.
    private func applyAppearance() {
        NSApp.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
    }

    /// Resizes the window between the classic layout and iPod proportions.
    /// Pins the *content* size (not the frame) so the body fills the window
    /// exactly, with no leftover strip below the iPod.
    private func morphWindow(toIPod ipod: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else { return }

        let contentSize = ipod ? IPodMetrics.bodySize : Self.classicMinSize
        if ipod {
            savedFrame = window.frame
            window.styleMask.remove(.resizable)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
        } else {
            window.styleMask.insert(.resizable)
            window.contentMinSize = contentSize
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                           height: CGFloat.greatestFiniteMagnitude)
        }

        var frame: NSRect
        if ipod {
            frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        } else {
            frame = savedFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 640)
        }
        frame.origin = NSPoint(
            x: window.frame.midX - frame.width / 2,
            y: window.frame.maxY - frame.height
        )
        window.setFrame(frame, display: true, animate: true)
    }

    @ViewBuilder
    private var mainArea: some View {
        if library.source == .rockbox {
            RockboxView()
        } else if library.folderPath == nil {
            emptyState(
                icon: "folder.badge.plus",
                title: "Welcome to iPod Connect",
                message: "Choose your music folder and iPod Connect will build your library from the FLAC (and other audio) files inside it.",
                buttonTitle: "Choose Music Folder…"
            ) {
                library.chooseFolder()
            }
        } else if library.tracks.isEmpty && !library.isScanning {
            emptyState(
                icon: "music.note.list",
                title: "No Music Found",
                message: "No audio files were found in the chosen folder. Pick a different folder or rescan.",
                buttonTitle: "Choose Music Folder…"
            ) {
                library.chooseFolder()
            }
        } else {
            switch library.source {
            case .music:
                switch library.musicViewMode {
                case .list: TrackListView()
                case .coverFlow: CoverFlowView()
                }
            case .artists: ArtistsView()
            case .albums: AlbumsView()
            case .rockbox: RockboxView()
            }
        }
    }

    private func emptyState(
        icon: String, title: String, message: String,
        buttonTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.emptyGlyph)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.emptyTitle)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(buttonTitle, action: action)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.contentBG)
    }
}

/// Configures the NSWindow for the classic single-surface iTunes look:
/// content under a transparent title bar, draggable by the toolbar area.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.title = "iPod Connect"
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
