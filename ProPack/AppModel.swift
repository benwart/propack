import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case idle
        case detecting
        case testing
        case connected(PPVersion)
        case failed(String)

        var isBusy: Bool { self == .detecting || self == .testing }
        var isConnected: Bool { if case .connected = self { true } else { false } }
    }

    enum ExportState {
        case idle
        case running(ExportProgress)
        case airDropping(playlistName: String)
        case airDropFinished(playlistName: String)
        case finished(ExportResult)
        case failed(String)
    }

    enum ImportState {
        case idle
        case inspecting
        case ready(ImportPackage)
        case importing(package: ImportPackage, progress: ImportProgress)
        case finished(ImportResult)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .inspecting, .importing: true
            default: false
            }
        }
    }

    // Connection
    private(set) var connection: ConnectionState = .idle
    private(set) var connectedPort: Int?

    // Playlists
    private(set) var playlists: [PPPlaylistNode] = []
    private(set) var playlistsError: String?
    private(set) var isLoadingPlaylists = false
    var selectedPlaylistID: String? {
        didSet { if oldValue != selectedPlaylistID { Task { await preparePlan() } } }
    }

    // Plan / preview
    private(set) var plan: ExportPlan?
    private(set) var planProgress: ExportProgress?
    private(set) var planError: String?

    // Library
    private(set) var manualLibraryURL: URL?
    private(set) var discoveredLibraryURL: URL?

    // Export
    private(set) var exportState: ExportState = .idle
    var includeMediaInExport: Bool = true
    var includeThemesInExport: Bool = true
    var includeFontsInExport: Bool = true

    // Import
    var importState: ImportState = .idle
    var isImportSheetPresented: Bool = false
    var songConflictPolicy: SongConflictPolicy = .rename
    var playlistConflictPolicy: PlaylistConflictPolicy = .keepBoth
    var targetGroupName: String = ""
    var groupConflictPolicy: GroupConflictPolicy = .useExisting
    var selectedTargetLibraryURL: URL?

    private var planTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var currentAirDropTempDirectory: URL?

    private static let libraryBookmarkKey = "libraryBookmark"

    init() {
        AirDropService.purgeAllTemporaryFiles()
        ImportService.purgeAllStagingDirectories()
        manualLibraryURL = Self.restoreLibraryBookmark()
    }

    var client: ProPresenterClient? { connectedPort.map { ProPresenterClient(port: $0) } }

    var selectedPlaylist: PPPlaylistNode? {
        selectedPlaylistID.flatMap { PPPlaylistNode.find($0, in: playlists) }
    }

    var isExporting: Bool {
        switch exportState {
        case .running, .airDropping: true
        default: false
        }
    }

    // MARK: Connection

    /// Auto-detects the port. Returns it so the view can persist it in `@AppStorage`.
    func autodetect() async -> Int? {
        connection = .detecting
        do {
            let detection = try await PortDetector().detect()
            await didConnect(port: detection.port, version: detection.version)
            return detection.port
        } catch {
            connection = .failed(error.localizedDescription)
            return nil
        }
    }

    func testConnection(port: Int) async {
        guard (1...65535).contains(port) else {
            connection = .failed("Enter a port between 1 and 65535.")
            return
        }
        connection = .testing
        do {
            let version = try await PortDetector().verify(port: port)
            await didConnect(port: port, version: version)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    /// On launch: try the saved port first, then fall back to auto-detection.
    func connectOnLaunch(savedPort: Int) async -> Int? {
        if savedPort > 0 {
            await testConnection(port: savedPort)
            if connection.isConnected { return savedPort }
        }
        return await autodetect()
    }

    func disconnect() {
        planTask?.cancel()
        connection = .idle
        connectedPort = nil
        playlists = []
        selectedPlaylistID = nil
        plan = nil
    }

    private func didConnect(port: Int, version: PPVersion) async {
        connectedPort = port
        connection = .connected(version)
        await reloadPlaylists()
    }

    // MARK: Playlists

    func reloadPlaylists() async {
        guard let client else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            playlists = try await client.playlists()
            playlistsError = nil
            if let id = selectedPlaylistID, PPPlaylistNode.find(id, in: playlists) != nil {
                await preparePlan()
            } else {
                let sortedLeaves = PPPlaylistNode.search(nodes: playlists, query: "", sortOption: .dateDescending)
                selectedPlaylistID = sortedLeaves.first?.node.id ?? PPPlaylistNode.leaves(of: playlists).first?.id
            }
        } catch {
            playlistsError = error.localizedDescription
        }
    }

    func preparePlan() async {
        planTask?.cancel()
        plan = nil
        planError = nil
        exportState = .idle
        guard let client, let id = selectedPlaylistID, selectedPlaylist?.isGroup == false else {
            planProgress = nil
            return
        }
        let service = ExportService(client: client, additionalLibraryRoots: [manualLibraryURL].compactMap { $0 })
        planProgress = .init(phase: .fetching, message: "Loading playlist…", fraction: nil)

        let task = Task { [weak self] in
            do {
                let plan = try await service.prepare(playlistID: id) { progress in
                    Task { @MainActor in
                        guard let self, self.selectedPlaylistID == id else { return }
                        self.planProgress = progress
                    }
                }
                guard let self, !Task.isCancelled, self.selectedPlaylistID == id else { return }
                self.plan = plan
                if let root = plan.discoveredLibraryRoot { self.discoveredLibraryURL = root }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.selectedPlaylistID == id else { return }
                self.planError = error.localizedDescription
            }
            if let self, !Task.isCancelled, self.selectedPlaylistID == id { self.planProgress = nil }
        }
        planTask = task
        await task.value
    }

    // MARK: Library folder

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose ProPresenter Libraries Folder"
        panel.message = "Select the folder containing your ProPresenter libraries (usually Documents ▸ ProPresenter ▸ Libraries)."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = discoveredLibraryURL
            ?? LibraryLocator.defaultLibraryRoots.first { FileManager.default.fileExists(atPath: $0.path) }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setManualLibrary(url)
    }

    func clearManualLibrary() {
        manualLibraryURL?.stopAccessingSecurityScopedResource()
        manualLibraryURL = nil
        UserDefaults.standard.removeObject(forKey: Self.libraryBookmarkKey)
        Task { await preparePlan() }
    }

    private func setManualLibrary(_ url: URL) {
        manualLibraryURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        manualLibraryURL = url
        // Security-scoped bookmarks persist access if the app is ever sandboxed; plain bookmarks otherwise.
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        UserDefaults.standard.set(bookmark, forKey: Self.libraryBookmarkKey)
        Task { await preparePlan() }
    }

    private static func restoreLibraryBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: libraryBookmarkKey) else { return nil }
        var stale = false
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        _ = url?.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: Export

    func beginExport() {
        guard let plan, let client, !isExporting else { return }

        let panel = NSSavePanel()
        panel.title = "Export Playlist Package"
        let propackType = UTType(filenameExtension: "propack") ?? .data
        panel.allowedContentTypes = [propackType, .zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportService.suggestedArchiveName(for: plan.playlist.name)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let service = ExportService(client: client)
        let includeMedia = includeMediaInExport
        let includeThemes = includeThemesInExport
        let includeFonts = includeFontsInExport
        exportState = .running(.init(phase: .staging, message: "Preparing…", fraction: 0))
        exportTask = Task { [weak self] in
            do {
                let result = try await service.export(
                    plan: plan,
                    to: destination,
                    includeMedia: includeMedia,
                    includeThemes: includeThemes,
                    includeFonts: includeFonts
                ) { progress in
                    Task { @MainActor in
                        guard let self, self.isExporting else { return }
                        self.exportState = .running(progress)
                    }
                }
                guard let self else { return }
                self.exportState = .finished(result)
                let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
                var exportedParts = ["\(result.includedFiles) presentation(s)"]
                if result.includedMediaFiles > 0 { exportedParts.append("\(result.includedMediaFiles) media file(s)") }
                if result.includedThemeFiles > 0 { exportedParts.append("\(result.includedThemeFiles) theme(s)") }
                if result.includedFontFiles > 0 { exportedParts.append("\(result.includedFontFiles) font(s)") }
                let record = TransferRecord(
                    type: .export,
                    playlistName: plan.playlist.name,
                    presentationCount: result.includedFiles,
                    mediaCount: result.includedMediaFiles,
                    filePath: destination.path,
                    fileSizeBytes: fileSizeBytes,
                    status: .completed,
                    detail: "Exported \(exportedParts.joined(separator: ", ")) to \(destination.lastPathComponent)"
                )
                TransferHistoryStore.shared.record(record)
            } catch is CancellationError {
                self?.exportState = .idle
            } catch {
                self?.exportState = .failed(error.localizedDescription)
            }
        }
    }

    /// Exports the playlist to an isolated temporary folder, opens the native AirDrop dialog,
    /// and deletes the temporary files once the transfer completes or is dismissed.
    func beginAirDrop() {
        guard let plan, let client, !isExporting else { return }

        AirDropService.purgeAllTemporaryFiles()

        let tempDirectory: URL
        do {
            tempDirectory = try AirDropService.createTemporaryExportDirectory()
        } catch {
            exportState = .failed("Could not prepare temporary export directory: \(error.localizedDescription)")
            return
        }

        currentAirDropTempDirectory = tempDirectory
        let fileName = ExportService.suggestedArchiveName(for: plan.playlist.name)
        let archiveDestination = tempDirectory.appending(path: fileName)

        let service = ExportService(client: client)
        let includeMedia = includeMediaInExport
        let includeThemes = includeThemesInExport
        let includeFonts = includeFontsInExport
        exportState = .running(.init(phase: .staging, message: "Preparing AirDrop package…", fraction: 0))

        exportTask = Task { [weak self] in
            do {
                let result = try await service.export(
                    plan: plan,
                    to: archiveDestination,
                    includeMedia: includeMedia,
                    includeThemes: includeThemes,
                    includeFonts: includeFonts
                ) { progress in
                    Task { @MainActor in
                        guard let self, self.isExporting else { return }
                        self.exportState = .running(progress)
                    }
                }

                guard let self, !Task.isCancelled else {
                    AirDropService.cleanup(directoryURL: tempDirectory)
                    return
                }

                self.exportState = .airDropping(playlistName: plan.playlist.name)

                let airDrop = AirDropService(
                    directoryURL: tempDirectory,
                    archiveURL: result.archiveURL,
                    playlistName: plan.playlist.name
                ) { [weak self] airDropResult in
                    Task { @MainActor in
                        guard let self else { return }
                        self.currentAirDropTempDirectory = nil
                        switch airDropResult {
                        case .success:
                            var parts = ["\(result.includedFiles) presentation(s)"]
                            if result.includedMediaFiles > 0 { parts.append("\(result.includedMediaFiles) media file(s)") }
                            if result.includedThemeFiles > 0 { parts.append("\(result.includedThemeFiles) theme(s)") }
                            if result.includedFontFiles > 0 { parts.append("\(result.includedFontFiles) font(s)") }
                            let record = TransferRecord(
                                type: .airdrop,
                                playlistName: plan.playlist.name,
                                presentationCount: result.includedFiles,
                                mediaCount: result.includedMediaFiles,
                                filePath: nil,
                                fileSizeBytes: (try? FileManager.default.attributesOfItem(atPath: result.archiveURL.path)[.size] as? NSNumber)?.int64Value,
                                status: .completed,
                                detail: "Transferred \(parts.joined(separator: ", ")) via AirDrop"
                            )
                            TransferHistoryStore.shared.record(record)
                            self.exportState = .airDropFinished(playlistName: plan.playlist.name)
                        case .failure(let error):
                            if case AirDropService.AirDropError.cancelled = error {
                                self.exportState = .idle
                            } else {
                                self.exportState = .failed(error.localizedDescription)
                            }
                        }
                    }
                }
                airDrop.start()
            } catch is CancellationError {
                AirDropService.cleanup(directoryURL: tempDirectory)
                self?.currentAirDropTempDirectory = nil
                self?.exportState = .idle
            } catch {
                AirDropService.cleanup(directoryURL: tempDirectory)
                self?.currentAirDropTempDirectory = nil
                self?.exportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        if let temp = currentAirDropTempDirectory {
            AirDropService.cleanup(directoryURL: temp)
            currentAirDropTempDirectory = nil
        }
        exportState = .idle
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Import

    var availableLibraries: [URL] {
        var urls: [URL] = []

        func appendLibraryRootOrChildren(_ root: URL) {
            if root.lastPathComponent == "Libraries" {
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    var addedChild = false
                    for child in children {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                            urls.append(child)
                            addedChild = true
                        }
                    }
                    if addedChild { return }
                }
            }
            if FileManager.default.fileExists(atPath: root.path) {
                urls.append(root)
            }
        }

        if let manual = manualLibraryURL { appendLibraryRootOrChildren(manual) }
        if let activeLib = LibraryLocator.configuredActiveLibraryDirectory { urls.append(activeLib) }
        if let discovered = discoveredLibraryURL { appendLibraryRootOrChildren(discovered) }
        for root in LibraryLocator.defaultLibraryRoots {
            appendLibraryRootOrChildren(root)
        }
        return LibraryLocator.normalizedRoots(urls)
    }

    func choosePackageToImport() {
        let panel = NSOpenPanel()
        panel.title = "Import ProPack Playlist Package"
        panel.message = "Select a ProPack package (.propack or .zip) to import into ProPresenter."
        let propackType = UTType(filenameExtension: "propack") ?? .data
        panel.allowedContentTypes = [propackType, .zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPackageForImport(url: url)
    }

    func openPackageForImport(url: URL) {
        importTask?.cancel()
        importState = .inspecting
        isImportSheetPresented = true

        importTask = Task { [weak self] in
            guard let self else { return }
            let service = ImportService(client: self.client)
            do {
                if self.discoveredLibraryURL == nil, let client = self.client {
                    if let apiDetected = await LibraryLocator.discoverActiveLibraryFromAPI(client: client) {
                        self.discoveredLibraryURL = apiDetected.firstLibraryFolder ?? apiDetected.librariesRoot
                    }
                }
                let package = try await service.inspect(archiveURL: url)
                guard !Task.isCancelled else { return }
                self.importState = .ready(package)
                if self.selectedTargetLibraryURL == nil {
                    self.selectedTargetLibraryURL = self.availableLibraries.first
                }
            } catch is CancellationError {
                self.importState = .idle
                self.isImportSheetPresented = false
            } catch {
                self.importState = .failed(error.localizedDescription)
            }
        }
    }

    func startImport() {
        guard case .ready(let package) = importState,
              let targetLib = selectedTargetLibraryURL ?? availableLibraries.first else { return }

        importState = .importing(package: package, progress: .init(phase: .copying, message: "Starting import…", fraction: 0))
        let service = ImportService(client: self.client)

        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.executeImport(
                    package: package,
                    targetLibraryURL: targetLib,
                    songConflictPolicy: self.songConflictPolicy,
                    playlistConflictPolicy: self.playlistConflictPolicy,
                    targetGroupName: self.targetGroupName.isEmpty ? nil : self.targetGroupName,
                    groupConflictPolicy: self.groupConflictPolicy
                ) { progress in
                    Task { @MainActor in
                        self.importState = .importing(package: package, progress: progress)
                    }
                }
                self.importState = .finished(result)
                var summaryParts: [String] = []
                if result.importedSongsCount > 0 { summaryParts.append("\(result.importedSongsCount) imported") }
                if result.renamedSongsCount > 0 { summaryParts.append("\(result.renamedSongsCount) renamed") }
                if result.skippedSongsCount > 0 { summaryParts.append("\(result.skippedSongsCount) skipped") }
                if result.importedMediaCount > 0 { summaryParts.append("\(result.importedMediaCount) media") }
                if result.importedThemesCount > 0 { summaryParts.append("\(result.importedThemesCount) theme(s)") }
                if result.importedFontsCount > 0 { summaryParts.append("\(result.importedFontsCount) font(s)") }
                let detailMsg = "\(package.playlistName) → \(result.targetLibraryName) (\(summaryParts.joined(separator: ", ")))"
                let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: package.archiveURL.path)[.size] as? NSNumber)?.int64Value
                let record = TransferRecord(
                    type: .import,
                    playlistName: package.playlistName,
                    presentationCount: result.importedSongsCount + result.renamedSongsCount,
                    mediaCount: result.importedMediaCount,
                    filePath: package.archiveURL.path,
                    fileSizeBytes: fileSizeBytes,
                    status: .completed,
                    detail: detailMsg
                )
                TransferHistoryStore.shared.record(record)
                await self.reloadPlaylists()
            } catch is CancellationError {
                self.importState = .idle
                self.isImportSheetPresented = false
            } catch {
                self.importState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        ImportService.purgeAllStagingDirectories()
        importState = .idle
        isImportSheetPresented = false
    }

    func dismissImportSheet() {
        ImportService.purgeAllStagingDirectories()
        importState = .idle
        isImportSheetPresented = false
    }
}
