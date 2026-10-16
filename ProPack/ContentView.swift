import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("proPresenterPort") private var port: Int = 0
    @AppStorage(LayoutDefaults.leftColumnWidthKey) private var leftColumnWidth: Double = LayoutDefaults.defaultLeftColumnWidth
    private var showConnectionSheetState = State(initialValue: false)
    private var showHistorySheetState = State(initialValue: false)

    var body: some View {
        NavigationSplitView {
            PlaylistSidebar()
                .navigationSplitViewColumnWidth(
                    min: CGFloat(LayoutDefaults.minLeftColumnWidth),
                    ideal: CGFloat(leftColumnWidth),
                    max: CGFloat(LayoutDefaults.maxLeftColumnWidth)
                )
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
                    showHistorySheetState.wrappedValue = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .help("Transfer History & Audit Log")
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
        .sheet(isPresented: showHistorySheetState.projectedValue) {
            TransferHistoryView()
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
        .background(WindowFrameTracker())
    }
}

// MARK: - Connection

@MainActor
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

@MainActor
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

@MainActor
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

@MainActor
struct PlaylistSidebar: View {
    @Environment(AppModel.self) private var model
    @AppStorage(LayoutDefaults.playlistSortOptionKey) private var sortOptionRaw: String = PlaylistSortOption.dateDescending.rawValue
    @AppStorage(LayoutDefaults.playlistViewModeKey) private var viewMode: String = "tree"
    @AppStorage(LayoutDefaults.leftColumnWidthKey) private var leftColumnWidth: Double = LayoutDefaults.defaultLeftColumnWidth

    private var searchText: String {
        get { model.playlistSearchText }
        nonmutating set { model.playlistSearchText = newValue }
    }

    private var sortOption: PlaylistSortOption {
        get { PlaylistSortOption(rawValue: sortOptionRaw) ?? .dateDescending }
        nonmutating set {
            sortOptionRaw = newValue.rawValue
            LayoutPreferences().saveSortOption(newValue)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [PlaylistRowItem] {
        PPPlaylistNode.search(nodes: model.playlists, query: searchText, sortOption: sortOption)
    }

    private var sortedTree: [PPPlaylistNode] {
        model.playlists.sortedTree(by: sortOption)
    }

    @ViewBuilder
    var body: some View {
        if !model.connection.isConnected {
            ContentUnavailableView("Not Connected", systemImage: "bolt.horizontal.circle",
                                   description: Text("Connect to ProPresenter to see playlists."))
        } else if model.isLoadingPlaylists && model.playlists.isEmpty {
            ProgressView()
        } else if model.playlists.isEmpty {
            ContentUnavailableView("No Playlists", systemImage: "music.note.list")
        } else {
            playlistList
        }
    }

    @ViewBuilder
    private var playlistList: some View {
        List(selection: Binding(get: { model.selectedPlaylistID }, set: { model.selectedPlaylistID = $0 })) {
            if let error = model.playlistsError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }

            if isSearching && searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if isSearching {
                Section {
                    ForEach(searchResults) { item in
                        playlistRow(for: item)
                            .tag(item.node.id)
                    }
                } header: {
                    HStack {
                        Text("\(searchResults.count) \(searchResults.count == 1 ? "match" : "matches")")
                        Spacer()
                        Button("Clear") {
                            searchText = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
            } else if viewMode == "flat" {
                let flatItems = PPPlaylistNode.search(nodes: model.playlists, query: "", sortOption: sortOption)
                Section {
                    ForEach(flatItems) { item in
                        playlistRow(for: item)
                            .tag(item.node.id)
                    }
                } header: {
                    HStack {
                        Text("All Playlists (\(flatItems.count))")
                        Spacer()
                        Text(sortOption.shortLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                let hasGroups = sortedTree.contains(where: \.isGroup)
                if hasGroups {
                    Section {
                        OutlineGroup(sortedTree, children: \.outlineChildren) { node in
                            treeNodeRow(for: node)
                                .tag(node.id)
                                .selectionDisabled(node.isGroup)
                        }
                    } header: {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            Text(sortOption.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        ForEach(sortedTree) { node in
                            treeNodeRow(for: node)
                                .tag(node.id)
                        }
                    } header: {
                        HStack {
                            Text("Playlists (\(sortedTree.count))")
                            Spacer()
                            Text(sortOption.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: Binding(get: { model.playlistSearchText }, set: { model.playlistSearchText = $0 }), placement: .sidebar, prompt: "Search playlists (fuzzy)…")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: Binding(get: { sortOption }, set: { sortOption = $0 })) {
                        ForEach(PlaylistSortOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Divider()
                    Picker("Display", selection: $viewMode) {
                        Label("Tree View", systemImage: "folder").tag("tree")
                        Label("Flat List", systemImage: "list.bullet").tag("flat")
                    }
                } label: {
                    Label("Sort & View", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort playlists by name or date (Default: Newest First)")

                Button {
                    Task { await model.reloadPlaylists() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.connection.isConnected || model.isLoadingPlaylists)
                .help("Reload playlists")
            }
        }
        .onChange(of: sortOptionRaw) { _, newValue in
            if let option = PlaylistSortOption(rawValue: newValue) {
                LayoutPreferences().saveSortOption(option)
            }
        }
        .onChange(of: viewMode) { _, newValue in
            LayoutPreferences().saveViewMode(newValue)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LeftColumnWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(LeftColumnWidthPreferenceKey.self) { newWidth in
            guard newWidth >= CGFloat(LayoutDefaults.minLeftColumnWidth) &&
                  newWidth <= CGFloat(LayoutDefaults.maxLeftColumnWidth) else { return }
            let existing = LayoutPreferences().leftColumnWidth
            if abs(Double(newWidth) - existing) >= 1.0 {
                LayoutPreferences().saveLeftColumnWidth(Double(newWidth))
                leftColumnWidth = Double(newWidth)
            }
        }
        .background(SplitViewTracker(columnWidth: $leftColumnWidth))
    }

    @ViewBuilder
    private func playlistRow(for item: PlaylistRowItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if let match = item.match, !match.matchedIndices.isEmpty {
                    Text(FuzzyMatcher.highlightedString(for: item.node.name, matchedIndices: match.matchedIndices))
                        .lineLimit(1)
                } else {
                    Text(item.node.name)
                        .lineLimit(1)
                }
                if let path = item.folderPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let dateStr = item.node.formattedDateString {
                Text(dateStr)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func treeNodeRow(for node: PPPlaylistNode) -> some View {
        HStack {
            Label(node.name, systemImage: node.isGroup ? "folder" : "music.note.list")
            Spacer()
            if !node.isGroup, let dateStr = node.formattedDateString {
                Text(dateStr)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Detail

@MainActor
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

@MainActor
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
                    groupBadges(for: entry)
                }
            }
            .width(min: 170, ideal: 260)
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

    @ViewBuilder
    private func groupBadges(for entry: ExportPlan.Entry) -> some View {
        let groups = (entry.presentation?.groups ?? []).filter { !($0.name ?? "").isEmpty }
        if groups.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    let name = group.name ?? ""
                    let color = GroupColorResolver.color(for: name, customColor: group.color)
                    GroupBadgeView(name: name, color: color)
                }
            }
            .help(groupSummary(entry))
        }
    }
}

@MainActor
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

@MainActor
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
                    if let plan = model.plan {
                        let hasMedia = !plan.referencedMedia.isEmpty
                        let hasThemes = !plan.referencedThemes.isEmpty
                        let hasFonts = !plan.referencedFonts.isEmpty

                        if hasMedia {
                            Toggle(isOn: Binding(
                                get: { model.includeMediaInExport },
                                set: { model.includeMediaInExport = $0 }
                            )) {
                                Label("Media (\(plan.referencedMedia.count))", systemImage: "photo.on.rectangle")
                                    .font(.callout)
                            }
                            .toggleStyle(.checkbox)
                            .help("Include \(plan.referencedMedia.count) referenced media files (\(plan.formattedMediaSize)) in the package")
                        }

                        if hasThemes {
                            Toggle(isOn: Binding(
                                get: { model.includeThemesInExport },
                                set: { model.includeThemesInExport = $0 }
                            )) {
                                Label("Themes (\(plan.referencedThemes.count))", systemImage: "paintbrush")
                                    .font(.callout)
                            }
                            .toggleStyle(.checkbox)
                            .help("Include \(plan.referencedThemes.count) Audience Look / presentation theme(s) (\(plan.referencedThemes.map(\.themeName).joined(separator: ", "))) in the package")
                        }

                        if hasFonts {
                            Toggle(isOn: Binding(
                                get: { model.includeFontsInExport },
                                set: { model.includeFontsInExport = $0 }
                            )) {
                                Label("Fonts (\(plan.referencedFonts.count))", systemImage: "textformat")
                                    .font(.callout)
                            }
                            .toggleStyle(.checkbox)
                            .help("Include \(plan.referencedFonts.count) custom font file(s) (\(plan.referencedFonts.map(\.fontName).joined(separator: ", "))) in the package")
                        }

                        if hasMedia || hasThemes || hasFonts {
                            Divider().frame(height: 16)
                        }
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
                Text("Exports .pro files, themes, fonts, and manifest.json as a package.").foregroundStyle(.secondary)
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
        var parts = ["\(result.includedFiles) presentation(s)"]
        if result.includedThemeFiles > 0 { parts.append("\(result.includedThemeFiles) theme(s)") }
        if result.includedFontFiles > 0 { parts.append("\(result.includedFontFiles) font(s)") }
        if result.includedMediaFiles > 0 { parts.append("\(result.includedMediaFiles) media") }
        var text = "Exported \(parts.joined(separator: ", ")) to \(result.archiveURL.lastPathComponent)"
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

// MARK: - Layout Persistence Helpers

private struct LeftColumnWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

@MainActor
struct WindowFrameTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowTrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowTrackingView: NSView {
    private var resizeObserver: Any?
    private var hasConfiguredWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window, !hasConfiguredWindow else { return }
        hasConfiguredWindow = true
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        window.setFrameAutosaveName("ProPackMainWindow")

        let prefs = LayoutPreferences()
        let savedSize = prefs.windowSize

        let screen = window.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let finalWidth = min(max(CGFloat(LayoutDefaults.minWindowWidth), savedSize.width), screenFrame.width)
        let finalHeight = min(max(CGFloat(LayoutDefaults.minWindowHeight), savedSize.height), screenFrame.height)

        var frame = window.frame
        let currentTopLeft = NSPoint(x: frame.origin.x, y: frame.origin.y + frame.size.height)
        frame.size = NSSize(width: finalWidth, height: finalHeight)
        frame.origin.y = currentTopLeft.y - finalHeight

        if frame.origin.x < screenFrame.minX { frame.origin.x = screenFrame.minX }
        if frame.origin.y < screenFrame.minY { frame.origin.y = screenFrame.minY }
        if frame.maxX > screenFrame.maxX { frame.origin.x = max(screenFrame.minX, screenFrame.maxX - frame.width) }
        if frame.maxY > screenFrame.maxY { frame.origin.y = max(screenFrame.minY, screenFrame.maxY - frame.height) }

        window.setFrame(frame, display: true, animate: false)

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let win = window else { return }
            let size = win.frame.size
            guard size.width >= CGFloat(LayoutDefaults.minWindowWidth) &&
                  size.height >= CGFloat(LayoutDefaults.minWindowHeight) else { return }
            LayoutPreferences().saveWindowSize(width: Double(size.width), height: Double(size.height))
        }
    }

    deinit {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

@MainActor
struct SplitViewTracker: NSViewRepresentable {
    @Binding var columnWidth: Double

    func makeNSView(context: Context) -> NSView {
        let view = SplitViewTrackingView()
        view.onWidthChanged = { [weak view] newWidth in
            _ = view
            columnWidth = newWidth
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let tracker = nsView as? SplitViewTrackingView {
            tracker.onWidthChanged = { newWidth in
                columnWidth = newWidth
            }
        }
    }
}

private final class SplitViewTrackingView: NSView {
    var onWidthChanged: ((Double) -> Void)?
    private var splitViewObserver: Any?
    private var hasConfiguredInitialPosition = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let splitView = findSplitView() else { return }

        if !hasConfiguredInitialPosition {
            hasConfiguredInitialPosition = true
            let savedWidth = LayoutPreferences().leftColumnWidth
            if savedWidth >= LayoutDefaults.minLeftColumnWidth {
                splitView.setPosition(CGFloat(savedWidth), ofDividerAt: 0)
            }
        }

        if splitViewObserver == nil {
            splitViewObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self, weak splitView] _ in
                guard let self, let splitView, let firstSubview = splitView.subviews.first else { return }
                let currentWidth = Double(firstSubview.frame.width)
                guard currentWidth >= LayoutDefaults.minLeftColumnWidth &&
                      currentWidth <= LayoutDefaults.maxLeftColumnWidth else { return }
                let existing = LayoutPreferences().leftColumnWidth
                if abs(currentWidth - existing) >= 1.0 {
                    LayoutPreferences().saveLeftColumnWidth(currentWidth)
                    self.onWidthChanged?(currentWidth)
                }
            }
        }
    }

    private func findSplitView() -> NSSplitView? {
        var current: NSView? = self.superview
        while let c = current {
            if let split = c as? NSSplitView { return split }
            current = c.superview
        }
        return nil
    }

    deinit {
        if let observer = splitViewObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

