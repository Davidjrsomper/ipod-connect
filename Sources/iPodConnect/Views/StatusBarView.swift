import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                Button {
                    library.ipodMode = true
                } label: {
                    Image(systemName: "ipod")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.iconTint)
                }
                .buttonStyle(.plain)
                .help("Switch to iPod view")

                Button {
                    player.shuffle.toggle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(player.shuffle ? Theme.accent : Theme.iconTint)
                }
                .buttonStyle(.plain)
                .help("Shuffle")

                Button {
                    switch player.repeatMode {
                    case .off: player.repeatMode = .all
                    case .all: player.repeatMode = .one
                    case .one: player.repeatMode = .off
                    }
                } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(player.repeatMode != .off ? Theme.accent : Theme.iconTint)
                }
                .buttonStyle(.plain)
                .help("Repeat")

                Spacer()

                if library.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }

                Button {
                    library.chooseFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.iconTint)
                }
                .buttonStyle(.plain)
                .help("Choose Music Folder…")
            }
            .padding(.horizontal, 12)

            Text(library.statusText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.statusText)
        }
        .frame(height: 23)
        .frame(maxWidth: .infinity)
        .background(Theme.statusGradient)
        .overlay(alignment: .top) { Theme.statusBorder.frame(height: 1) }
    }
}
