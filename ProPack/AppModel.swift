import AppKit
import Observation

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

    private var planTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var currentAirDropTempDirectory: URL?

    private static let libraryBookmarkKey = "libraryBookmark"

    init() {
        AirDropService.purgeAllTemporaryFiles()
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
                selectedPlaylistID = PPPlaylistNode.leaves(of: playlists).first?.id
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
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportService.suggestedArchiveName(for: plan.playlist.name)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let service = ExportService(client: client)
        exportState = .running(.init(phase: .staging, message: "Preparing…", fraction: 0))
        exportTask = Task { [weak self] in
            do {
                let result = try await service.export(plan: plan, to: destination) { progress in
                    Task { @MainActor in
                        guard let self, self.isExporting else { return }
                        self.exportState = .running(progress)
                    }
                }
                self?.exportState = .finished(result)
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
        exportState = .running(.init(phase: .staging, message: "Preparing AirDrop package…", fraction: 0))

        exportTask = Task { [weak self] in
            do {
                let result = try await service.export(plan: plan, to: archiveDestination) { progress in
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
}
