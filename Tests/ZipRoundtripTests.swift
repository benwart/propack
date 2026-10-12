import Foundation

@MainActor
func runZipRoundtripTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "ExportService & ImportService roundtrip archive") {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: "ProPackRoundtripTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let libraryDir = tempDir.appending(path: "Library")
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)

        let testProFile = libraryDir.appending(path: "Cornerstone.pro")
        let fileContent = "Fake ProPresenter Binary Data: \(UUID().uuidString)"
        try fileContent.write(to: testProFile, atomically: true, encoding: .utf8)

        let plan = ExportPlan(
            playlist: PPIdentifier(uuid: "test-playlist-uuid", name: "Youth Night", index: 0),
            proPresenter: PPVersion(
                name: "ProPresenter",
                platform: "macOS",
                osVersion: "14.5",
                hostDescription: "ProPresenter 7.16.2",
                apiVersion: "v1"
            ),
            entries: [
                .init(
                    item: PPPlaylistItem(
                        identifier: PPIdentifier(uuid: "item-1", name: "Cornerstone", index: 0),
                        type: "presentation",
                        isHidden: false,
                        presentationInfo: PPPresentationInfo(
                            presentationUuid: "pres-1",
                            arrangementName: "Default",
                            arrangementUuid: "arr-1"
                        )
                    ),
                    presentation: PPPresentation(
                        identifier: PPIdentifier(uuid: "pres-1", name: "Cornerstone", index: 0),
                        groups: [
                            PPGroup(name: "Chorus", color: nil, slides: [
                                PPSlide(enabled: true, text: "Christ alone", label: "Chorus 1")
                            ])
                        ]
                    ),
                    fetchError: nil,
                    match: LibraryLocator.Match(url: testProFile, method: .fileName)
                )
            ],
            libraryRoots: [libraryDir],
            discoveredLibraryRoot: libraryDir,
            preparedAt: Date()
        )

        let archiveURL = tempDir.appending(path: "Youth Night.propack")
        let exportService = ExportService()
        let result = try await exportService.export(plan: plan, to: archiveURL)

        try assertEqual(result.includedFiles, 1)
        try assertTrue(fm.fileExists(atPath: archiveURL.path), "Archive file should exist on disk")

        // Now inspect the generated package using ImportService
        let importService = ImportService()
        let package = try await importService.inspect(archiveURL: archiveURL)

        try assertEqual(package.playlistName, "Youth Night")
        try assertEqual(package.presentations.count, 1)

        let presentation = package.presentations[0]
        try assertEqual(presentation.name, "Cornerstone")
        try assertTrue(fm.fileExists(atPath: presentation.stagedFileURL.path))

        let unpackedContent = try String(contentsOf: presentation.stagedFileURL, encoding: .utf8)
        try assertEqual(unpackedContent, fileContent)

        // Clean up staged package
        try? fm.removeItem(at: package.stagingDirectory)
    }
}
