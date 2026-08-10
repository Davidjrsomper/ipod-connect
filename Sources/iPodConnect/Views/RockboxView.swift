import SwiftUI

/// The Rockbox panel: device status, firmware install, and the theme gallery.
struct RockboxView: View {
    @EnvironmentObject var rockbox: RockboxManager
    @State private var showBootloaderConfirm = false
    @State private var showFormatSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            DeviceBar(showBootloaderConfirm: $showBootloaderConfirm,
                      showFormatSheet: $showFormatSheet)
            if !rockbox.preflightIssues.isEmpty { PreflightWarnings() }
            if rockbox.isBusy { busyBar }
            if let message = rockbox.statusMessage { banner(message, isError: false) }
            if let message = rockbox.errorMessage { banner(message, isError: true) }
            Divider()
            themeGallery
        }
        .background(Theme.contentBG)
        .task {
            rockbox.refreshDevices()
            if rockbox.themes.isEmpty { await rockbox.loadThemes() }
        }
        .sheet(isPresented: $showFormatSheet) {
            FormatSheet().environmentObject(rockbox)
        }
        .confirmationDialog(
            "Install the Rockbox bootloader?",
            isPresented: $showBootloaderConfirm,
            titleVisibility: .visible
        ) {
            let warned = !rockbox.preflightIssues.isEmpty
            if rockbox.activeTarget.bootloader == .dfu {
                Button(warned ? "Install Anyway" : "Continue", role: .destructive) {
                    Task { await rockbox.installClassicBootloader() }
                }
            } else {
                Button(warned ? "Install Anyway" : "Back Up Firmware and Install", role: .destructive) {
                    Task { await rockbox.installBootloader() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !rockbox.preflightIssues.isEmpty {
                Text(rockbox.preflightIssues.map { "\($0.title).\n\n\($0.detail)" }
                        .joined(separator: "\n\n")
                     + "\n\nInstalling now will very likely leave the iPod unable to start Rockbox.")
            } else if rockbox.activeTarget.bootloader == .dfu {
                Text("""
                This sends new boot firmware to your iPod over USB.

                You'll be asked to hold MENU and SELECT together to put the iPod into DFU mode. No administrator password is needed.

                If anything goes wrong the iPod stays in DFU mode, and you can always restore it in Finder — so this is recoverable, but don't unplug it while it's writing.
                """)
            } else {
                Text("""
                This writes to your iPod's firmware partition and needs your administrator password.

                Your existing firmware is backed up first, and the install is abandoned if that backup fails. A wrong or interrupted write can leave the iPod unbootable until you restore it in iTunes/Finder.

                Do not unplug the iPod until this finishes.
                """)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Rockbox")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.headerText)
            Spacer()
            Text("Release \(RockboxCatalog.release)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }

    private var busyBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rockbox.busyMessage ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.listText)
            ProgressView(value: rockbox.progress)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowAlt)
    }

    private func banner(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : Theme.accent)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.listText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                rockbox.statusMessage = nil
                rockbox.errorMessage = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.rowAlt)
    }

    private var themeGallery: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Themes for \(rockbox.activeTarget.name)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                if rockbox.isLoadingThemes {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                } else {
                    Text("\(rockbox.visibleThemes.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                TextField("Search themes", text: $rockbox.themeSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 170)
                Button {
                    Task { await rockbox.loadThemes(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.iconTint)
                .help("Re-download the theme list")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if let error = rockbox.themeError {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.emptyGlyph)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { Task { await rockbox.loadThemes() } }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190), spacing: 16, alignment: .top)],
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(rockbox.visibleThemes) { theme in
                            ThemeCell(theme: theme)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

// MARK: - Device bar

struct DeviceBar: View {
    @EnvironmentObject var rockbox: RockboxManager
    @Binding var showBootloaderConfirm: Bool
    @Binding var showFormatSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rockbox.devices.isEmpty {
                noDevice
            } else {
                device
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebarBG)
    }

    private var noDevice: some View {
        HStack(spacing: 8) {
            Image(systemName: "cable.connector")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text("No iPod connected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                Text("Connect an iPod in disk mode. You can still browse themes below.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            targetPicker
            Button("Rescan") { rockbox.refreshDevices() }
                .controlSize(.small)
        }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ipod")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rockbox.selectedDevice?.volumeName ?? "iPod")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.listText)
                    Text(rockbox.selectedDevice?.statusText ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if rockbox.selectedDevice?.isRockboxed != true { targetPicker }
                Button("Rescan") { rockbox.refreshDevices() }
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button(rockbox.selectedDevice?.isRockboxed == true
                       ? "Update Rockbox \(RockboxCatalog.release)"
                       : "Install Rockbox \(RockboxCatalog.release)") {
                    Task { await rockbox.installFirmware() }
                }
                .controlSize(.small)
                .disabled(rockbox.isBusy)

                Button("Install Bootloader…") { showBootloaderConfirm = true }
                    .controlSize(.small)
                    .disabled(rockbox.isBusy)
                Button("Format as FAT32…") { showFormatSheet = true }
                    .controlSize(.small)
                    .disabled(rockbox.isBusy)
                Spacer()
            }

            if rockbox.waitingForDFU {
                DFUPrompt()
            } else if rockbox.activeTarget.bootloader == .dfu {
                Text("The Classic installs its bootloader over USB. You'll be asked to hold MENU and SELECT when the time comes — no password needed.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !rockbox.installedThemes.isEmpty {
                InstalledThemesRow()
            }
        }
    }

    private var targetPicker: some View {
        Picker("", selection: $rockbox.manualTarget) {
            ForEach(RockboxTarget.all) { target in
                Text(target.name).tag(target)
            }
        }
        .labelsHidden()
        .frame(width: 190)
        .controlSize(.small)
        .onChange(of: rockbox.manualTarget) { _ in
            Task { await rockbox.loadThemes() }
        }
    }
}

/// Themes already on the device — switching between them is instant, with no
/// download.
struct InstalledThemesRow: View {
    @EnvironmentObject var rockbox: RockboxManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On this iPod")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.sidebarHeaderText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rockbox.installedThemes, id: \.self) { name in
                        let isActive = rockbox.activeTheme == name
                        Button {
                            rockbox.activate(themeNamed: name)
                        } label: {
                            Text(name)
                                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? .white : Theme.listText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(isActive
                                        ? AnyShapeStyle(Theme.rowSelGradient)
                                        : AnyShapeStyle(Theme.contentBG))
                                )
                                .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(isActive ? "Active theme" : "Switch to \(name)")
                    }
                }
            }
        }
    }
}

// MARK: - Theme cell

struct ThemeCell: View {
    @EnvironmentObject var rockbox: RockboxManager
    let theme: RockboxTheme
    @State private var isHovering = false

    private var canInstall: Bool {
        rockbox.selectedDevice?.isRockboxed == true && !rockbox.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let image = rockbox.preview(for: theme) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Theme.artPlaceholder
                        Image(systemName: "paintbrush")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.artGlyph)
                    }
                }
            }
            .frame(height: 132)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.06))
            .clipped()
            .border(Theme.artBorder, width: 1)
            .overlay(alignment: .bottomTrailing) {
                if isHovering && canInstall {
                    Menu {
                        Button("Install and Use") {
                            Task { await rockbox.install(theme: theme, activate: true) }
                        }
                        Button("Install Only") {
                            Task { await rockbox.install(theme: theme, activate: false) }
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Theme.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24)
                    .padding(6)
                }
            }

            Text(theme.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
                .padding(.top, 5)
            Text("\(theme.author) · \(theme.sizeText)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .help(theme.about.isEmpty ? theme.name : theme.about)
        .onHover { isHovering = $0 }
        .task { await rockbox.loadPreview(for: theme) }
    }
}


/// Shown while the app waits for a Classic to appear in DFU mode.
struct DFUPrompt: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hold MENU and SELECT together now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                Text("Keep holding — about 8 seconds. The screen goes blank and stays blank; that's DFU mode, and the install starts on its own. Let go once this message disappears.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.rowAlt)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}


/// Flags the two things that make a bootloader install fail after the fact:
/// a non-FAT32 iPod, and Rockbox not being installed yet.
struct PreflightWarnings: View {
    @EnvironmentObject var rockbox: RockboxManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rockbox.preflightIssues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.listText)
                        Text(issue.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowAlt)
        .overlay(alignment: .top) { Theme.headerBorder.frame(height: 1) }
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }
}


/// Erasing someone's iPod deserves more than an OK button, so this asks them
/// to type the device's name — the same pattern Disk Utility and GitHub use
/// for destructive actions.
struct FormatSheet: View {
    @EnvironmentObject var rockbox: RockboxManager
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var deviceName: String { rockbox.selectedDevice?.volumeName ?? "" }
    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(deviceName) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Format “\(deviceName)” as FAT32?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.emptyTitle)

            Text("""
            This erases every song and file on the iPod. It cannot be undone.

            Only the music partition is reformatted — a bootloader already installed stays where it is.

            FAT32 is the only format Rockbox can read, so this is the step that makes an iPod which won't boot into Rockbox start working.
            """)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Type **\(deviceName)** to confirm:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                TextField("", text: $typed)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erase and Format") {
                    dismiss()
                    Task { await rockbox.formatAsFAT32() }
                }
                .disabled(!matches)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Theme.contentBG)
    }
}
