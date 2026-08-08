import SwiftUI

/// The connected-iPod panel: capacity bar, what's on the device, and adding
/// or removing music — the old iTunes device screen, for a Rockboxed iPod.
struct DeviceView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var rockbox: RockboxManager
    @EnvironmentObject var device: DeviceManager

    @State private var selection = Set<String>()
    @State private var showAddSheet = false

    private var mount: String? { rockbox.selectedDevice?.mountPath }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let ipod = rockbox.selectedDevice {
                summary(ipod)
                if !ipod.isRockboxed {
                    stockFirmwareNotice
                } else {
                    if device.isWorking { workingBar }
                    if let message = device.statusMessage { banner(message, isError: false) }
                    if let message = device.errorMessage { banner(message, isError: true) }
                    trackList
                    capacityBar
                }
            } else {
                notConnected
            }
        }
        .background(Theme.contentBG)
        .task {
            rockbox.refreshDevices()
            device.refresh(mount: mount)
        }
        .onChange(of: rockbox.selectedDeviceID) { _, _ in
            selection.removeAll()
            device.refresh(mount: mount)
        }
        .sheet(isPresented: $showAddSheet) {
            AddToDeviceSheet(mount: mount ?? "")
                .environmentObject(library)
                .environmentObject(device)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(rockbox.selectedDevice?.volumeName ?? "iPod")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.headerText)
            Spacer()
            Button("Rescan") { rockbox.refreshDevices(); device.refresh(mount: mount) }
                .controlSize(.small)
            if let mount {
                Button("Eject") { device.eject(mount: mount) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }

    private func summary(_ ipod: ConnectedIPod) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "ipod")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(ipod.volumeName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                Text(ipod.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                if let capacity = device.capacity {
                    Text("\(device.deviceTracks.count) songs · \(capacity.freeText) free of \(capacity.totalText)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if ipod.isRockboxed {
                Button("Add Music…") { showAddSheet = true }
                    .controlSize(.regular)
                    .disabled(device.isWorking || library.tracks.isEmpty)
            }
        }
        .padding(14)
        .background(Theme.sidebarBG)
    }

    private var stockFirmwareNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.emptyGlyph)
            Text("This iPod is running Apple's firmware")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.emptyTitle)
            Text("""
                Adding music to a stock iPod means writing Apple's iTunesDB database — copying files alone leaves them invisible to the iPod. iPod Connect syncs to Rockboxed iPods only.

                Install Rockbox from the Rockbox panel, then come back here.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Open Rockbox Panel") { library.source = .rockbox }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notConnected: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 34))
                .foregroundStyle(Theme.emptyGlyph)
            Text("No iPod Connected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.emptyTitle)
            Text("Connect an iPod in disk mode. On a stock iPod, turn on “Enable disk use” in Finder first.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Rescan") { rockbox.refreshDevices() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workingBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.progressLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
            ProgressView(value: device.progress).progressViewStyle(.linear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                device.statusMessage = nil
                device.errorMessage = nil
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

    private var trackList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("On This iPod")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                Text("\(device.visibleDeviceTracks.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                TextField("Search device", text: $device.deviceSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 160)
                Button("Remove") {
                    guard let mount else { return }
                    let chosen = device.deviceTracks.filter { selection.contains($0.id) }
                    Task {
                        await device.remove(chosen, fromMount: mount)
                        selection.removeAll()
                    }
                }
                .controlSize(.small)
                .disabled(selection.isEmpty || device.isWorking)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            DeviceListHeader()

            if device.deviceTracks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.emptyGlyph)
                    Text("No music on this iPod yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(device.visibleDeviceTracks.enumerated()), id: \.element.id) { index, track in
                            DeviceRow(
                                track: track,
                                isSelected: selection.contains(track.id),
                                isAlternate: !index.isMultiple(of: 2)
                            )
                            .onTapGesture {
                                if selection.contains(track.id) { selection.remove(track.id) }
                                else { selection.insert(track.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var capacityBar: some View {
        VStack(spacing: 3) {
            if let capacity = device.capacity {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.artPlaceholder)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Theme.rowSelTop, Theme.rowSelBottom],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: max(2, geo.size.width * capacity.usedFraction))
                    }
                }
                .frame(height: 12)
                Text("\(capacity.freeText) free of \(capacity.totalText)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.statusGradient)
    }
}

struct DeviceListHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 24)
            Text("Name").padding(.leading, 4)
            Spacer(minLength: 8)
            Text("Artist").frame(width: 150, alignment: .leading)
            Text("Album").frame(width: 150, alignment: .leading)
            Text("Size").frame(width: 70, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.headerText)
        .frame(height: 19)
        .background(Theme.headerGradient)
        .overlay(alignment: .bottom) { Theme.headerBorder.frame(height: 1) }
    }
}

struct DeviceRow: View {
    let track: DeviceTrack
    let isSelected: Bool
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white : Theme.secondaryText)
                .frame(width: 24)
            Text(track.name)
                .foregroundStyle(isSelected ? .white : Theme.listText)
                .lineLimit(1)
                .padding(.leading, 4)
            Spacer(minLength: 8)
            Text(track.artist)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(track.album)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(track.sizeText)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryText)
                .frame(width: 70, alignment: .leading)
        }
        .font(.system(size: 11))
        .frame(height: 20)
        .background(isSelected ? AnyView(Theme.rowSelGradient)
                               : AnyView(isAlternate ? Theme.rowAlt : Theme.contentBG))
        .contentShape(Rectangle())
    }
}

/// Picks library tracks to copy across.
struct AddToDeviceSheet: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var device: DeviceManager
    @Environment(\.dismiss) private var dismiss

    let mount: String
    @State private var selection = Set<String>()
    @State private var search = ""

    private var candidates: [Track] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = library.tracks.sorted {
            if $0.sortArtist != $1.sortArtist {
                return $0.sortArtist.localizedStandardCompare($1.sortArtist) == .orderedAscending
            }
            if $0.album != $1.album {
                return $0.album.localizedStandardCompare($1.album) == .orderedAscending
            }
            return $0.trackNumber < $1.trackNumber
        }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedTracks: [Track] {
        library.tracks.filter { selection.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        IPodSync.bytesRequired(for: selectedTracks, onVolume: mount)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Music to iPod")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.emptyTitle)
                Spacer()
                TextField("Search library", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 190)
            }
            .padding(12)
            .background(Theme.headerGradient)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, track in
                        let onDevice = IPodSync.isOnDevice(track, mount: mount)
                        HStack(spacing: 6) {
                            Image(systemName: selection.contains(track.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(onDevice ? Theme.tertiaryText : Theme.secondaryText)
                                .frame(width: 20)
                            Text(track.title)
                                .foregroundStyle(Theme.listText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if onDevice {
                                Text("on iPod")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(track.artist)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                            Text(track.format)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 46, alignment: .leading)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .frame(height: 20)
                        .background(index.isMultiple(of: 2) ? Theme.contentBG : Theme.rowAlt)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selection.contains(track.id) { selection.remove(track.id) }
                            else { selection.insert(track.id) }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Select All") { selection = Set(candidates.map(\.id)) }
                    .controlSize(.small)
                Button("None") { selection.removeAll() }
                    .controlSize(.small)
                Spacer()
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Button("Cancel") { dismiss() }
                Button("Copy to iPod") {
                    let tracks = selectedTracks
                    dismiss()
                    Task { await device.copy(tracks, toMount: mount) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(12)
            .background(Theme.statusGradient)
        }
        .frame(width: 640, height: 480)
        .background(Theme.contentBG)
    }

    private var summaryText: String {
        guard !selection.isEmpty else { return "Nothing selected" }
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
        let free = device.capacity.map { " · \($0.freeText) free" } ?? ""
        return "\(selection.count) selected · \(size) to copy\(free)"
    }
}
