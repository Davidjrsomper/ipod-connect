import SwiftUI
import AVFoundation

@main
struct iPodConnectApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Player()
    @StateObject private var updaterViewModel = UpdaterViewModel()
    @StateObject private var rockbox = RockboxManager()
    @AppStorage("darkMode") private var darkMode = false

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--verify"), i + 1 < args.count {
            Self.verify(path: args[i + 1])
        }
    }

    /// Headless self-test: parse tags and confirm Core Audio can decode the file.
    private static func verify(path: String) {
        let url = URL(fileURLWithPath: path)
        if let info = FLACParser.parse(url: url) {
            print("tags: title=\(info.title ?? "-") artist=\(info.artist ?? "-") album=\(info.album ?? "-") "
                + "genre=\(info.genre ?? "-") track=\(info.trackNumber.map(String.init) ?? "-") "
                + "duration=\(String(format: "%.2f", info.duration))s "
                + "\(info.sampleRate)Hz/\(info.bitsPerSample)bit")
        } else {
            print("tags: not a FLAC file or parse failed")
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0
            player.play()
            Thread.sleep(forTimeInterval: 0.6)
            print("playback: decoded OK, position=\(String(format: "%.2f", player.currentTime))s of \(String(format: "%.2f", player.duration))s")
            exit(0)
        } catch {
            print("playback: FAILED — \(error)")
            exit(1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(rockbox)
                .onAppear {
                    library.load()
                    library.rescan()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterViewModel.controller.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Choose Music Folder…") { library.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Rescan Library") { library.rescan() }
                    .keyboardShortcut("r")
                    .disabled(library.folderPath == nil)
                Divider()
                Button("Add Missing Album Art…") { library.showMissingArtwork = true }
                    .disabled(library.tracks.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Dark Mode", isOn: $darkMode)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Toggle("iPod View", isOn: $library.ipodMode)
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
            }
            CommandMenu("Controls") {
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button(player.shuffle ? "Shuffle Off" : "Shuffle On") { player.shuffle.toggle() }
                Button("Cycle Repeat Mode") {
                    switch player.repeatMode {
                    case .off: player.repeatMode = .all
                    case .all: player.repeatMode = .one
                    case .one: player.repeatMode = .off
                    }
                }
                Divider()
                Button("Volume Up") { player.volume = min(1, player.volume + 0.1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") { player.volume = max(0, player.volume - 0.1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }
        }
    }
}
