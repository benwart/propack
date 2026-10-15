import Foundation

@MainActor
func main() async {
    print("========================================")
    print("       ProPack Automated Test Suite     ")
    print("========================================\n")

    await runPPVersionTests()
    await runManifestTests()
    await runConflictResolutionTests()
    await runMediaLocatorTests()
    await runThemeAndFontLocatorTests()
    await runTransferHistoryTests()
    await runZipRoundtripTests()
    await runPlaylistFilterTests()

    let code = TestSuite.shared.report()
    exit(code)
}

await main()
