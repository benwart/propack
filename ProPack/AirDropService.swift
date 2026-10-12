import AppKit
import Foundation

/// Coordinates direct AirDrop sharing and manages temporary export files with automatic cleanup.
@MainActor
final class AirDropService: NSObject, NSSharingServiceDelegate {
    enum AirDropError: LocalizedError {
        case serviceUnavailable
        case cancelled
        case transferFailed(String)

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable:
                "AirDrop is not available on this Mac or cannot accept archive files."
            case .cancelled:
                "AirDrop transfer was cancelled."
            case .transferFailed(let message):
                "AirDrop transfer failed: \(message)"
            }
        }
    }

    /// Base directory for temporary AirDrop exports: `<temp>/ProPack/AirDrop/`
    static var baseTemporaryDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ProPack", directoryHint: .isDirectory)
            .appending(path: "AirDrop", directoryHint: .isDirectory)
    }

    /// The native AirDrop service icon provided by macOS AppKit, if available.
    static var airDropIcon: NSImage? {
        NSSharingService(named: .sendViaAirDrop)?.image
    }

    /// Whether AirDrop is supported and enabled on this Mac.
    static var isAirDropAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    private let directoryURL: URL
    private let archiveURL: URL
    private let playlistName: String
    private let completion: (Result<Void, Error>) -> Void

    /// Keeps controller instances alive while the native AirDrop sheet is open.
    private static var activeControllers = Set<AirDropService>()

    init(
        directoryURL: URL,
        archiveURL: URL,
        playlistName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.directoryURL = directoryURL
        self.archiveURL = archiveURL
        self.playlistName = playlistName
        self.completion = completion
        super.init()
    }

    /// Prepares a fresh isolated temporary directory for an AirDrop export.
    static func createTemporaryExportDirectory() throws -> URL {
        let dir = baseTemporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes all temporary files created by AirDrop exports across all sessions.
    static func purgeAllTemporaryFiles() {
        try? FileManager.default.removeItem(at: baseTemporaryDirectory)
    }

    /// Removes a specific temporary directory immediately.
    static func cleanup(directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// Initiates the AirDrop transfer for the given archive.
    func start() {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: [archiveURL]) else {
            completion(.failure(AirDropError.serviceUnavailable))
            Self.cleanup(directoryURL: directoryURL)
            return
        }

        Self.activeControllers.insert(self)
        service.delegate = self
        service.perform(withItems: [archiveURL])
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(result: .success(()))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.userCancelled.rawValue {
            finish(result: .failure(AirDropError.cancelled))
        } else {
            finish(result: .failure(AirDropError.transferFailed(error.localizedDescription)))
        }
    }

    private func finish(result: Result<Void, Error>) {
        completion(result)

        // Allow a 4-second grace period for background daemon transfer completion before removing files
        let dir = directoryURL
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            Self.cleanup(directoryURL: dir)
        }

        Self.activeControllers.remove(self)
    }
}
