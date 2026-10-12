import Foundation

@MainActor
func runTransferHistoryTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "TransferRecord.codable serialization and deserialization") {
        let record = TransferRecord(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            type: .export,
            playlistName: "Sunday Morning",
            presentationCount: 5,
            mediaCount: 3,
            filePath: "/tmp/Sunday.propack",
            fileSizeBytes: 20480,
            status: .completed,
            detail: "Exported 5 presentation(s) and 3 media file(s)"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TransferRecord.self, from: data)

        try assertEqual(decoded.id, record.id)
        try assertEqual(decoded.type, .export)
        try assertEqual(decoded.playlistName, "Sunday Morning")
        try assertEqual(decoded.presentationCount, 5)
        try assertEqual(decoded.mediaCount, 3)
        try assertEqual(decoded.status, .completed)
        try assertEqual(decoded.fileSizeBytes, 20480)
        try assertEqual(decoded.formattedFileSize, "20 KB")
    }

    await suite.run(name: "TransferHistoryStore persistence, insertion, and cap limit") {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "propack-history-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appending(path: "history.json")
        let store = TransferHistoryStore(storageURL: fileURL, maxRecords: 3)

        try assertEqual(store.records.count, 0)

        // Insert 4 records to test capacity limit (max 3)
        for i in 1...4 {
            let record = TransferRecord(
                type: .import,
                playlistName: "Playlist \(i)",
                presentationCount: i,
                mediaCount: 0,
                status: .completed,
                detail: "Import #\(i)"
            )
            store.record(record)
        }

        try assertEqual(store.records.count, 3)
        // Most recent should be Playlist 4
        try assertEqual(store.records.first?.playlistName, "Playlist 4")
        // Oldest retained should be Playlist 2 (Playlist 1 trimmed)
        try assertEqual(store.records.last?.playlistName, "Playlist 2")

        // Reload store from disk
        let reloadedStore = TransferHistoryStore(storageURL: fileURL, maxRecords: 3)
        try assertEqual(reloadedStore.records.count, 3)
        try assertEqual(reloadedStore.records.first?.playlistName, "Playlist 4")

        // Test clear
        reloadedStore.clear()
        try assertEqual(reloadedStore.records.count, 0)

        let emptyStore = TransferHistoryStore(storageURL: fileURL, maxRecords: 3)
        try assertEqual(emptyStore.records.count, 0)
    }
}
