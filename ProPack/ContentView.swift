import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("proPresenterPort") private var port: Int = 0
    private var showConnectionSheetState = State(initialValue: false)

    var body: some View {
        NavigationSplitView {
            PlaylistSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if model.connection.isConnected {
                PlaylistDetailView()
            } else {
                ScrollView {
                    ConnectionSetupView(port: $port)
                        .padding(32)
                        .frame(maxWidth: 620)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showConnectionSheetState.wrappedValue = true } label: {
                    ConnectionBadge(state: model.connection, port: model.connectedPort)
                }
                .help("Connection settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.choosePackageToImport()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .help("Import a ProPack package into ProPresenter (Cmd+I)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "help")
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .help("Open ProPack Help (Cmd+?)")
            }
        }
        .sheet(isPresented: showConnectionSheetState.projectedValue) {
            VStack(spacing: 0) {
                ScrollView { ConnectionSetupView(port: $port).padding(24) }
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { showConnectionSheetState.wrappedValue = false }.keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(width: 560, height: 600)
        }
        .sheet(isPresented: Binding(
            get: { model.isImportSheetPresented },
            set: { model.isImportSheetPresented = $0 }
        )) {
            ImportSheetView()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                let url: URL?
                if let u = item as? URL {
                    url = u
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url, ["propack", "zip"].contains(url.pathExtension.lowercased()) {
                    Task { @MainActor in
                        model.openPackageForImport(url: url)
                    }
                }
            }
            return true
        }
        .task {
            if let detected = await model.connectOnLaunch(savedPort: port) { port = detected }
        }
    }
}

// MARK: - Connection

struct ConnectionBadge: View {
    let state: AppModel.ConnectionState
    let port: Int?

    var body: some View {
        HStack(spacing: 6) {
            if state.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).font(.callout)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch state {
        case .connected: .green
        case .failed: .red
        case .idle, .detecting, .testing: .secondary
        }
    }

    private var label: String {
        switch state {
        case .idle: "Not connected"
        case .detecting: "Detecting…"
        case .testing: "Testing…"
        case .connected: "Connected · \(port.map(String.init) ?? "?")"
        case .failed: "Not connected"
        }
    }
}

struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    @Binding var port: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                if let iconImage = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage {
                    Image(nsImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Connect to ProPresenter").font(.title2.bold())
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("v\(version)")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("ProPack reads playlists from ProPresenter's local network API and packages the matching .pro files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Port")
                        TextField("e.g. 50001", value: $port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onSubmit { Task { await model.testConnection(port: port) } }
                        Button("Test Connection") { Task { await model.testConnection(port: port) } }
                            .disabled(model.connection.isBusy)
                        Button("Auto-Detect") {
                            Task { if let detected = await model.autodetect() { port = detected } }
                        }
                        .disabled(model.connection.isBusy)
                    }
                    statusRow
                }
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Setup").font(.headline)
                SetupStep(number: 1, title: "Open ProPresenter", detail: "ProPresenter must be running on this Mac.")
                SetupStep(number: 2, title: "Open Settings ▸ Network",
                          detail: "In ProPresenter, choose ProPresenter ▸ Settings… and select the Network tab.")
                SetupStep(number: 3, title: "Enable Network",
                          detail: "Turn on “Enable Network”. ProPresenter assigns a port (often in the 50000–65000 range) and shows it next to the toggle.")
                SetupStep(number: 4, title: "Connect",
                          detail: "Click Auto-Detect, or type the port shown in ProPresenter and click Test Connection.")
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch model.connection {
        case .idle:
            Label("Not connected", systemImage: "circle.dashed").foregroundStyle(.secondary)
        case .detecting:
            Label("Looking for ProPresenter…", systemImage: "magnifyingglass").foregroundStyle(.secondary)
        case .testing:
            Label("Testing port \(port.formatted(.number.grouping(.never)))…", systemImage: "network").foregroundStyle(.secondary)
        case .connected(let version):
            Label("Connected to \(version.displayString)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold().monospacedDigit())
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Sidebar

struct PlaylistSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding(get: { model.selectedPlaylistID }, set: { model.selectedPlaylistID = $0 })) {
            if let error = model.playlistsError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Section("Playlists") {
                OutlineGroup(model.playlists, children: \.outlineChildren) { node in
                    Label(node.name, systemImage: node.isGroup ? "folder" : "music.note.list")
                        .tag(node.id)
                        .selectionDisabled(node.isGroup)
                }
            }
        }
        .overlay {
            if !model.connection.isConnected {
                ContentUnavailableView("Not Connected", systemImage: "bolt.horizontal.circle",
                                       description: Text("Connect to ProPresenter to see playlists."))
            } else if model.isLoadingPlaylists && model.playlists.isEmpty {
                ProgressView()
            } else if model.playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.reloadPlaylists() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.connection.isConnected || model.isLoadingPlaylists)
                .help("Reload playlists")
            }
        }
    }
}

// MARK: - Detail

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let playlist = model.selectedPlaylist, !playlist.isGroup {
            VStack(spacing: 0) {
                content
                Divider()
                ExportBar()
                    .padding()
                    .background(.bar)
            }
            .navigationTitle(playlist.name)
            .navigationSubtitle(subtitle)
        } else {
            ContentUnavailableView("Select a Playlist", systemImage: "music.note.list",
                                   description: Text("Choose a playlist in the sidebar to preview and export it."))
        }
    }

    private var subtitle: String {
        guard let plan = model.plan else { return "" }
        return "\(plan.presentationEntries.count) presentations · \(plan.resolvedCount) files found"
    }

    @ViewBuilder private var content: some View {
        if let plan = model.plan {
            VStack(spacing: 0) {
                PresentationTable(entries: plan.entries)
                Divider()
                LibraryBar(plan: plan).padding(.horizontal).padding(.vertical, 10)
            }
        } else if let error = model.planError {
            ContentUnavailableView {
                Label("Couldn't Load Playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await model.preparePlan() } }
            }
        } else if let progress = model.planProgress {
            VStack(spacing: 12) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).frame(width: 240)
                } else {
                    ProgressView()
                }
                Text(progress.message).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}

struct PresentationTable: View {
    let entries: [ExportPlan.Entry]

    var body: some View {
        Table(entries) {
            TableColumn("") { entry in
                statusIcon(entry)
            }
            .width(22)
            TableColumn("Item") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.item.name)
                        .foregroundStyle(entry.isPresentation ? .primary : .secondary)
                    if !entry.isPresentation {
                        Text(entry.item.kind.capitalized).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            TableColumn("Arrangement") { entry in
                Text(entry.item.presentationInfo?.arrangementNameIfSet ?? (entry.isPresentation ? "Default" : ""))
                    .foregroundStyle(entry.item.presentationInfo?.arrangementNameIfSet == nil ? .secondary : .primary)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Groups") { entry in
                if entry.isPresentation {
                    Text(groupSummary(entry)).foregroundStyle(.secondary).lineLimit(1)
                        .help(groupSummary(entry))
                }
            }
            TableColumn("File") { entry in
                if let match = entry.match {
                    Text(match.url.lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                        .help("\(match.url.path)\nMatched by: \(match.method.rawValue)")
                } else if entry.isPresentation {
                    Text(entry.fetchError ?? "Not found").foregroundStyle(.red).lineLimit(1)
                        .help(entry.fetchError ?? "No matching .pro file found in the library folders.")
                }
            }
        }
    }

    @ViewBuilder private func statusIcon(_ entry: ExportPlan.Entry) -> some View {
        if !entry.isPresentation {
            Image(systemName: "minus").foregroundStyle(.tertiary).help("Not a presentation — listed in manifest only")
        } else if entry.match != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("File found")
        } else {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("File not found")
        }
    }

    private func groupSummary(_ entry: ExportPlan.Entry) -> String {
        let names = (entry.presentation?.groups ?? []).compactMap(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }
}

struct LibraryBar: View {
    @Environment(AppModel.self) private var model
    let plan: ExportPlan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "books.vertical").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Library").font(.caption).foregroundStyle(.secondary)
                Text(libraryDescription).lineLimit(1).truncationMode(.middle)
                    .help(plan.libraryRoots.map(\.path).joined(separator: "\n"))
            }
            Spacer()
            if model.manualLibraryURL != nil {
                Button("Use Automatic") { model.clearManualLibrary() }
            }
            Button("Choose Folder…") { model.chooseLibraryFolder() }
            Button {
                Task { await model.preparePlan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Re-scan library")
        }
        .font(.callout)
    }

    private var libraryDescription: String {
        if let manual = model.manualLibraryURL { return "\(manual.path) (manual)" }
        if let discovered = plan.discoveredLibraryRoot { return "\(discovered.path) (from ProPresenter)" }
        if let first = plan.libraryRoots.first { return "\(first.path) (default)" }
        return "No library folder found — choose one"
    }
}

struct ExportBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer()
            if model.isExporting {
                Button("Cancel") { model.cancelExport() }
            } else {
                HStack(spacing: 8) {
                    if let plan = model.plan, !plan.referencedMedia.isEmpty {
                        Toggle(isOn: Binding(
                            get: { model.includeMediaInExport },
                            set: { model.includeMediaInExport = $0 }
                        )) {
                            Label("Media (\(plan.referencedMedia.count))", systemImage: "photo.on.rectangle")
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                        .help("Include \(plan.referencedMedia.count) referenced media files (\(plan.formattedMediaSize)) in the package")
                        Divider().frame(height: 16)
                    }

                    Button {
                        model.beginAirDrop()
                    } label: {
                        Label {
                            Text("AirDrop")
                        } icon: {
                            if let icon = AirDropService.airDropIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "paperplane")
                            }
                        }
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.plan == nil || model.plan?.resolvedCount == 0)
                    .help("Send playlist package directly via AirDrop (Cmd+Shift+A)")

                    Button {
                        model.beginExport()
                    } label: {
                        Label("Save to Disk…", systemImage: "arrow.down.doc")
                    }
                    .keyboardShortcut("e")
                    .buttonStyle(.borderedProminent)
                    .disabled(model.plan == nil || model.plan?.resolvedCount == 0)
                    .help("Save playlist package to disk (Cmd+E)")
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.exportState {
        case .idle:
            if let plan = model.plan, plan.missingCount > 0 {
                Label("\(plan.missingCount) presentation file(s) not found — they'll be listed in the manifest as missing.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Text("Exports .pro files and manifest.json as a .zip package.").foregroundStyle(.secondary)
            }
        case .running(let progress):
            HStack(spacing: 10) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).frame(width: 160)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text("\(progress.phase.rawValue): \(progress.message)").lineLimit(1).foregroundStyle(.secondary)
            }
        case .airDropping(let name):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sharing “\(name)” via AirDrop…").lineLimit(1).foregroundStyle(.secondary)
            }
        case .airDropFinished(let name):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("AirDropped “\(name)” · Temporary files cleared").lineLimit(1)
            }
        case .finished(let result):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(finishedMessage(result)).lineLimit(1)
                Button("Show in Finder") { model.revealInFinder(result.archiveURL) }
                    .buttonStyle(.link)
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
        }
    }

    private func finishedMessage(_ result: ExportResult) -> String {
        var text = "Exported \(result.includedFiles) file(s) to \(result.archiveURL.lastPathComponent)"
        if !result.missingPresentations.isEmpty { text += " (\(result.missingPresentations.count) missing)" }
        return text
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(AppModel())
            .frame(width: 960, height: 620)
    }
}
#endif
