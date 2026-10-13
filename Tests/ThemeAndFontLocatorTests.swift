import Foundation

@MainActor
func runThemeAndFontLocatorTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "PPLookSummary.parse extracts presentation_theme from live look JSON") {
        let json = """
        {
            "id": {
                "uuid": "look-live-1",
                "name": "Sunday Stream Look",
                "index": 0
            },
            "screens": [
                {
                    "screen": { "uuid": "scr-1", "name": "Main Projector" },
                    "enabled": true,
                    "slide": {
                        "enabled": true,
                        "presentation_theme": null
                    }
                },
                {
                    "screen": { "uuid": "scr-2", "name": "Livestream Output" },
                    "enabled": true,
                    "layers": [
                        {
                            "type": "slide",
                            "enabled": true,
                            "presentation_theme": {
                                "uuid": "theme-uuid-lower-thirds",
                                "name": "Lower Thirds Stream",
                                "index": 1
                            }
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let parsed = PPLookSummary.parse(from: json, isLive: true)
        let unwrapped = try assertNotNil(parsed, "Should parse PPLookSummary")
        try assertEqual(unwrapped.name, "Sunday Stream Look")
        try assertTrue(unwrapped.isLive == true)
        try assertEqual(unwrapped.referencedThemes.count, 1)
        try assertEqual(unwrapped.referencedThemes.first?.uuid, "theme-uuid-lower-thirds")
        try assertEqual(unwrapped.referencedThemes.first?.name, "Lower Thirds Stream")
    }

    await suite.run(name: "ThemeLocator.findReferencedThemes resolves themes from Audience Look and .pro data") {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: "ProPackThemeTest-\(UUID().uuidString)")
        let themesDir = tempDir.appending(path: "Themes")
        let subThemeDir = themesDir.appending(path: "Livestream")
        try fm.createDirectory(at: subThemeDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Theme 1: matched by Audience Look theme name/UUID
        let lowerThirdsFile = subThemeDir.appending(path: "Lower Thirds Stream")
        try "ProtoThemeData UUID: theme-uuid-lower-thirds {\n\\fonttbl{\\f0\\fnil\\fcharset0 BrandFont-Bold;}}".write(
            to: lowerThirdsFile, atomically: true, encoding: .utf8
        )

        // Theme 2: Unused theme in Themes directory (should NOT be bundled)
        let unusedThemeFile = themesDir.appending(path: "Unused Sermon Theme")
        try "ProtoThemeData UUID: 99999999-9999-4999-9999-999999999999".write(
            to: unusedThemeFile, atomically: true, encoding: .utf8
        )

        let proFile = tempDir.appending(path: "Amazing Grace.pro")
        try "PresentationData LookCue: look-special-uuid".write(to: proFile, atomically: true, encoding: .utf8)

        let liveLook = PPLookSummary(
            identifier: PPIdentifier(uuid: "look-live-1", name: "Default Look", index: 0),
            isLive: true,
            referencedThemes: [
                PPIdentifier(uuid: "theme-uuid-lower-thirds", name: "Lower Thirds Stream", index: 0)
            ]
        )

        let resolved = ThemeLocator.findReferencedThemes(
            inProFiles: [proFile],
            audienceLooks: [liveLook],
            themeRoots: [themesDir]
        )

        try assertEqual(resolved.count, 1)
        try assertEqual(resolved[0].themeName, "Lower Thirds Stream")
        try assertEqual(resolved[0].relativePath, "Livestream/Lower Thirds Stream")
    }

    await suite.run(name: "FontLocator.extractFontNames and findReferencedFonts resolves custom fonts") {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: "ProPackFontTest-\(UUID().uuidString)")
        let fontsDir = tempDir.appending(path: "Fonts")
        try fm.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Create fake custom font files in custom font root
        let customFont1 = fontsDir.appending(path: "CMGSans-Bold.ttf")
        try "FakeTTFData-1".write(to: customFont1, atomically: true, encoding: .utf8)

        let customFont2 = fontsDir.appending(path: "Montserrat-SemiBold.otf")
        try "FakeOTFData-2".write(to: customFont2, atomically: true, encoding: .utf8)

        let unusedFont = fontsDir.appending(path: "UnusedScript.ttf")
        try "FakeTTFData-Unused".write(to: unusedFont, atomically: true, encoding: .utf8)

        // Create a .pro file referencing CMGSans-Bold in RTF fonttbl and a Theme file referencing Montserrat-SemiBold
        let proFile = tempDir.appending(path: "Song.pro")
        let proContent = """
        {\\rtf1\\ansi{\\fonttbl{\\f0\\fnil\\fcharset0 CMGSans-Bold;}{\\f1\\fswiss\\fcharset0 Helvetica;}}Amazing Grace}
        """
        try proContent.write(to: proFile, atomically: true, encoding: .utf8)

        let themeFile = tempDir.appending(path: "LowerThirds")
        let themeContent = "ThemeProtoData\u{00}Montserrat-SemiBold\u{00}"
        try themeContent.write(to: themeFile, atomically: true, encoding: .utf8)

        let extractedNames = FontLocator.extractFontNames(from: proContent.data(using: .utf8)!)
        try assertTrue(extractedNames.contains("CMGSans-Bold"), "Should extract CMGSans-Bold from RTF fonttbl")

        let resolvedFonts = FontLocator.findReferencedFonts(
            inFiles: [proFile, themeFile],
            fontRoots: [fontsDir],
            allowCoreTextLookup: false
        )

        try assertEqual(resolvedFonts.count, 2)
        let filenames = resolvedFonts.map(\.filename)
        try assertTrue(filenames.contains("CMGSans-Bold.ttf"))
        try assertTrue(filenames.contains("Montserrat-SemiBold.otf"))
        try assertTrue(!filenames.contains("UnusedScript.ttf"))
    }

    await suite.run(name: "LibraryLocator, ThemeLocator, and MediaLocator resolve workspace folders and Themes/<Name>/Theme layout") {
        let customWorkspace = URL(fileURLWithPath: "/Volumes/ProductionDrive/ProPresenterWorkspace")
        let targetLib = customWorkspace.appending(path: "Libraries/SundayService", directoryHint: .isDirectory)

        try assertEqual(
            LibraryLocator.workspaceDirectory(forTargetLibraryURL: targetLib).path,
            customWorkspace.path
        )
        try assertEqual(
            ThemeLocator.targetThemesDirectory(forTargetLibraryURL: targetLib).path,
            customWorkspace.appending(path: "Themes").path
        )
        try assertEqual(
            MediaLocator.targetMediaDirectory(forTargetLibraryURL: targetLib).path,
            customWorkspace.appending(path: "Media").path
        )

        let modernThemeURL = customWorkspace.appending(path: "Themes/UNITED/Theme")
        try assertEqual(ThemeLocator.logicalThemeName(for: modernThemeURL), "UNITED")
    }
}
