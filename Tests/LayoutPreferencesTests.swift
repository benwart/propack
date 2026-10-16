import CoreGraphics
import Foundation

@MainActor
func runLayoutPreferencesTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "LayoutPreferences.defaults are provided when empty") {
        let testDefaults = UserDefaults(suiteName: "test_layout_defaults_\(UUID().uuidString)")!
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }

        let prefs = LayoutPreferences(userDefaults: testDefaults)
        try assertEqual(prefs.windowSize.width, CGFloat(LayoutDefaults.defaultWindowWidth))
        try assertEqual(prefs.windowSize.height, CGFloat(LayoutDefaults.defaultWindowHeight))
        try assertEqual(prefs.leftColumnWidth, LayoutDefaults.defaultLeftColumnWidth)
        try assertEqual(prefs.sortOption, PlaylistSortOption.dateDescending)
        try assertEqual(prefs.viewMode, "tree")
    }

    await suite.run(name: "LayoutPreferences.windowSize saves on change and clamps min bounds") {
        let testDefaults = UserDefaults(suiteName: "test_layout_window_\(UUID().uuidString)")!
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }

        let prefs = LayoutPreferences(userDefaults: testDefaults)
        prefs.windowSize = CGSize(width: 1200, height: 750)

        try assertEqual(prefs.windowSize.width, 1200)
        try assertEqual(prefs.windowSize.height, 750)
        try assertEqual(testDefaults.double(forKey: LayoutDefaults.windowWidthKey), 1200)
        try assertEqual(testDefaults.double(forKey: LayoutDefaults.windowHeightKey), 750)

        // Attempting to set below min width/height is ignored
        prefs.windowSize = CGSize(width: 400, height: 300)
        try assertEqual(prefs.windowSize.width, 1200)
        try assertEqual(prefs.windowSize.height, 750)

        // saveWindowSize method
        prefs.saveWindowSize(width: 1100, height: 700)
        try assertEqual(prefs.windowSize.width, 1100)
        try assertEqual(prefs.windowSize.height, 700)
    }

    await suite.run(name: "LayoutPreferences.leftColumnWidth saves on change and clamps bounds") {
        let testDefaults = UserDefaults(suiteName: "test_layout_column_\(UUID().uuidString)")!
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }

        let prefs = LayoutPreferences(userDefaults: testDefaults)
        prefs.leftColumnWidth = 320.0

        try assertEqual(prefs.leftColumnWidth, 320.0)
        try assertEqual(testDefaults.double(forKey: LayoutDefaults.leftColumnWidthKey), 320.0)

        // Clamps below minimum
        prefs.leftColumnWidth = 150.0
        try assertEqual(prefs.leftColumnWidth, LayoutDefaults.minLeftColumnWidth)

        // Clamps above maximum
        prefs.leftColumnWidth = 800.0
        try assertEqual(prefs.leftColumnWidth, LayoutDefaults.maxLeftColumnWidth)

        // saveLeftColumnWidth method
        prefs.saveLeftColumnWidth(340.0)
        try assertEqual(prefs.leftColumnWidth, 340.0)
    }

    await suite.run(name: "LayoutPreferences.sortOption saves composite and component keys") {
        let testDefaults = UserDefaults(suiteName: "test_layout_sort_\(UUID().uuidString)")!
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }

        let prefs = LayoutPreferences(userDefaults: testDefaults)
        prefs.sortOption = .nameAscending

        try assertEqual(prefs.sortOption, .nameAscending)
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortOptionKey), "name_asc")
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortFieldKey), "name")
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortOrderKey), "ascending")

        prefs.saveSortOption(.dateAscending)
        try assertEqual(prefs.sortOption, .dateAscending)
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortOptionKey), "date_asc")
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortFieldKey), "date")
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistSortOrderKey), "ascending")

        // View mode
        prefs.saveViewMode("flat")
        try assertEqual(prefs.viewMode, "flat")
        try assertEqual(testDefaults.string(forKey: LayoutDefaults.playlistViewModeKey), "flat")
    }
}
