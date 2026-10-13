import Foundation

@MainActor
func runZipRoundtripTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "ExportService & ImportService roundtrip archive") {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: "ProPackRoundtripTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let libraryDir = tempDir.appending(path: "Libraries/Default", directoryHint: .isDirectory)
        let themesDir = tempDir.appending(path: "Themes/Livestream", directoryHint: .isDirectory)
        let fontsDir = tempDir.appending(path: "CustomFonts", directoryHint: .isDirectory)
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: fontsDir, withIntermediateDirectories: true)

        let testProFile = libraryDir.appending(path: "Cornerstone.pro")
        let fileContent = "Fake ProPresenter Binary Data: \(UUID().uuidString)"
        try fileContent.write(to: testProFile, atomically: true, encoding: .utf8)

        let testThemeFile = themesDir.appending(path: "Lower Thirds")
        let themeContent = "Fake Theme Protobuf Data: \(UUID().uuidString)"
        try themeContent.write(to: testThemeFile, atomically: true, encoding: .utf8)

        let testFontFile = fontsDir.appending(path: "BrandWorship-Bold.otf")
        let fontContent = "Fake OTF Font Binary: \(UUID().uuidString)"
        try fontContent.write(to: testFontFile, atomically: true, encoding: .utf8)

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
            referencedThemes: [
                ThemeAsset(
                    url: testThemeFile,
                    filename: "Lower Thirds",
                    relativePath: "Livestream/Lower Thirds",
                    themeName: "Lower Thirds",
                    sizeBytes: Int64(themeContent.utf8.count)
                )
            ],
            referencedFonts: [
                FontAsset(
                    url: testFontFile,
                    filename: "BrandWorship-Bold.otf",
                    fontName: "BrandWorship-Bold",
                    sizeBytes: Int64(fontContent.utf8.count)
                )
            ],
            audienceLooks: [
                PPLookSummary(
                    identifier: PPIdentifier(uuid: "look-1", name: "Sunday Look", index: 0),
                    isLive: true,
                    referencedThemes: [PPIdentifier(uuid: "theme-1", name: "Lower Thirds", index: 0)]
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
        try assertEqual(result.includedThemeFiles, 1)
        try assertEqual(result.includedFontFiles, 1)
        try assertTrue(fm.fileExists(atPath: archiveURL.path), "Archive file should exist on disk")

        // Now inspect the generated package using ImportService
        let importService = ImportService()
        let package = try await importService.inspect(archiveURL: archiveURL)

        try assertEqual(package.playlistName, "Youth Night")
        try assertEqual(package.presentations.count, 1)
        try assertEqual(package.themes.count, 1)
        try assertEqual(package.fonts.count, 1)
        try assertEqual(package.audienceLooks.count, 1)
        try assertEqual(package.audienceLooks.first?.name, "Sunday Look")

        let presentation = package.presentations[0]
        try assertEqual(presentation.name, "Cornerstone")
        try assertTrue(fm.fileExists(atPath: presentation.stagedFileURL.path))

        let unpackedContent = try String(contentsOf: presentation.stagedFileURL, encoding: .utf8)
        try assertEqual(unpackedContent, fileContent)

        // Execute import into a fresh target directory and verify themes & fonts are installed
        let importTargetRoot = tempDir.appending(path: "ImportedTarget", directoryHint: .isDirectory)
        let targetLibDir = importTargetRoot.appending(path: "Libraries/Default", directoryHint: .isDirectory)
        let targetThemesDir = importTargetRoot.appending(path: "Themes", directoryHint: .isDirectory)
        let targetFontsDir = importTargetRoot.appending(path: "Fonts", directoryHint: .isDirectory)

        let importResult = try await importService.executeImport(
            package: package,
            targetLibraryURL: targetLibDir,
            songConflictPolicy: .overwrite,
            playlistConflictPolicy: .skip,
            targetThemesURL: targetThemesDir,
            targetFontsURL: targetFontsDir
        )

        try assertEqual(importResult.importedSongsCount, 1)
        try assertEqual(importResult.importedThemesCount, 1)
        try assertEqual(importResult.importedFontsCount, 1)
        try assertTrue(fm.fileExists(atPath: targetThemesDir.appending(path: "Livestream/Lower Thirds").path))
        try assertTrue(fm.fileExists(atPath: targetFontsDir.appending(path: "BrandWorship-Bold.otf").path))
    }
}
