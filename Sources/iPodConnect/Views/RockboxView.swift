import SwiftUI

/// The Rockbox panel: device status, firmware install, and the theme gallery.
struct RockboxView: View {
    @EnvironmentObject var rockbox: RockboxManager
    @State private var showBootloaderConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            DeviceBar(showBootloaderConfirm: $showBootloaderConfirm)
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
        .confirmationDialog(
            "Install the Rockbox bootloader?",
            isPresented: $showBootloaderConfirm,
            titleVisibility: .visible
        ) {
            Button("Back Up Firmware and Install", role: .destructive) {
                Task { await rockbox.installBootloader() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This writes to your iPod's firmware partition and needs your administrator password.

            Your existing firmware is backed up first, and the install is abandoned if that backup fails. A wrong or interrupted write can leave the iPod unbootable until you restore it in iTunes/Finder.

            Do not unplug the iPod until this finishes.
            """)
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
                    Task { await rockbox.loadThemes() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.iconTint)
                .help("Reload theme list")
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

                if rockbox.activeTarget.bootloader == .ipodpatcher {
                    Button("Install Bootloader…") { showBootloaderConfirm = true }
                        .controlSize(.small)
                        .disabled(rockbox.isBusy)
                } else {
                    Link("Bootloader instructions for Classic",
                         destination: URL(string: "https://files.freemyipod.org/~user890104/bootloader-ipodclassic.html")!)
                        .font(.system(size: 11))
                }
                Spacer()
            }

            if rockbox.activeTarget.bootloader == .dfu {
                Text("The iPod Classic's bootloader must be installed over USB with the device in DFU mode — that step can't be automated here.")
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
        .onChange(of: rockbox.manualTarget) { _, _ in
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
