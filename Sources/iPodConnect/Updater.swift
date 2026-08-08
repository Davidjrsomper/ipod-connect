import SwiftUI
import Sparkle

/// Owns Sparkle's updater for the app's lifetime and exposes it to SwiftUI.
final class UpdaterViewModel: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true means Sparkle begins its periodic background
        // check (SUScheduledCheckInterval, set in Info.plist) immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

/// A "Check for Updates…" menu item that greys itself out while a check is
/// already running, matching Sparkle's recommended SwiftUI integration.
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
