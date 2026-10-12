import Foundation

// MARK: - Models

enum TransferType: String, Codable, CaseIterable, Sendable {
    case export = "Export"
    case airdrop = "AirDrop"
    case `import` = "Import"

    var iconName: String {
        switch self {
        case .export: "square.and.arrow.up"
        case .airdrop: "airdrop"
        case .import: "square.and.arrow.down"
        }
    }
}

enum TransferStatus: String, Codable, Sendable {
    case completed = "Completed"
    case failed = "Failed"

    var iconName: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }
}

struct TransferRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: TransferType
    let playlistName: String
    let presentationCount: Int
    let mediaCount: Int
    let filePath: String?
    let fileSizeBytes: Int64?
    let status: TransferStatus
    let detail: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: TransferType,
        playlistName: String,
        presentationCount: Int,
        mediaCount: Int = 0,
        filePath: String? = nil,
        fileSizeBytes: Int64? = nil,
        status: TransferStatus = .completed,
        detail: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.playlistName = playlistName
        self.presentationCount = presentationCount
        self.mediaCount = mediaCount
        self.filePath = filePath
        self.fileSizeBytes = fileSizeBytes
        self.status = status
        self.detail = detail
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var formattedFileSize: String? {
        guard let bytes = fileSizeBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var fileExistsOnDisk: Bool {
        guard let filePath else { return false }
        return FileManager.default.fileExists(atPath: filePath)
    }
}

// MARK: - Store

@MainActor
final class TransferHistoryStore: ObservableObject {
    static let shared = TransferHistoryStore()

    @Published private(set) var records: [TransferRecord] = []

    private let storageURL: URL
    private let maxRecords: Int

    nonisolated static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appending(path: "com.benwart.propack", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    init(storageURL: URL = defaultStorageURL, maxRecords: Int = 200) {
        self.storageURL = storageURL
        self.maxRecords = maxRecords
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            records = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([TransferRecord].self, from: data)
        } catch {
            print("Failed to load transfer history: \(error)")
            records = []
        }
    }

    func record(_ item: TransferRecord) {
        records.insert(item, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        records.removeAll()
        persist()
    }

    private func persist() {
        let parentDir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to persist transfer history: \(error)")
        }
    }
}
