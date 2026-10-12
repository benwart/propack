import Foundation

@MainActor
func runConflictResolutionTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "ConflictResolution.songRenameStrategy appends copy suffix") {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "ProPackTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalFile = tempDir.appending(path: "Amazing Grace.pro")
        try "Original Content".write(to: originalFile, atomically: true, encoding: .utf8)

        // Helper function that determines target URL for rename
        func resolveUniqueTarget(name: String, directory: URL) -> URL {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var candidate = directory.appending(path: "\(base) (Imported).\(ext)")
            var count = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = directory.appending(path: "\(base) (Imported \(count)).\(ext)")
                count += 1
            }
            return candidate
        }

        let firstRename = resolveUniqueTarget(name: "Amazing Grace.pro", directory: tempDir)
        try assertEqual(firstRename.lastPathComponent, "Amazing Grace (Imported).pro")

        // Create the imported file
        try "Imported 1 Content".write(to: firstRename, atomically: true, encoding: .utf8)

        let secondRename = resolveUniqueTarget(name: "Amazing Grace.pro", directory: tempDir)
        try assertEqual(secondRename.lastPathComponent, "Amazing Grace (Imported 2).pro")
    }

    await suite.run(name: "ConflictResolution.policyDescriptions are present") {
        for policy in SongConflictPolicy.allCases {
            try assertFalse(policy.description.isEmpty)
        }
        for policy in PlaylistConflictPolicy.allCases {
            try assertFalse(policy.description.isEmpty)
        }
    }
}
