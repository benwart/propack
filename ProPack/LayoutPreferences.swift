import CoreGraphics
import Foundation

// MARK: - Layout & Settings Constants

enum LayoutDefaults {
    static let defaultWindowWidth: Double = 1000.0
    static let defaultWindowHeight: Double = 640.0
    static let minWindowWidth: Double = 820.0
    static let minWindowHeight: Double = 520.0

    static let defaultLeftColumnWidth: Double = 260.0
    static let minLeftColumnWidth: Double = 220.0
    static let maxLeftColumnWidth: Double = 500.0

    static let windowWidthKey = "windowWidth"
    static let windowHeightKey = "windowHeight"
    static let leftColumnWidthKey = "leftColumnWidth"
    static let playlistSortOptionKey = "playlistSortOption"
    static let playlistSortFieldKey = "playlistSortField"
    static let playlistSortOrderKey = "playlistSortOrder"
    static let playlistViewModeKey = "playlistViewMode"
}

// MARK: - Layout Preferences Store

struct LayoutPreferences {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The saved window size, clamped to at least minWindowWidth x minWindowHeight.
    var windowSize: CGSize {
        get {
            let width = userDefaults.double(forKey: LayoutDefaults.windowWidthKey)
            let height = userDefaults.double(forKey: LayoutDefaults.windowHeightKey)
            let finalWidth = width >= LayoutDefaults.minWindowWidth ? width : LayoutDefaults.defaultWindowWidth
            let finalHeight = height >= LayoutDefaults.minWindowHeight ? height : LayoutDefaults.defaultWindowHeight
            return CGSize(width: finalWidth, height: finalHeight)
        }
        nonmutating set {
            guard newValue.width >= LayoutDefaults.minWindowWidth && newValue.height >= LayoutDefaults.minWindowHeight else { return }
            userDefaults.set(Double(newValue.width), forKey: LayoutDefaults.windowWidthKey)
            userDefaults.set(Double(newValue.height), forKey: LayoutDefaults.windowHeightKey)
            userDefaults.synchronize()
        }
    }

    /// The saved width of the left sidebar column, clamped to [minLeftColumnWidth, maxLeftColumnWidth].
    var leftColumnWidth: Double {
        get {
            let val = userDefaults.double(forKey: LayoutDefaults.leftColumnWidthKey)
            if val >= LayoutDefaults.minLeftColumnWidth && val <= LayoutDefaults.maxLeftColumnWidth {
                return val
            }
            return LayoutDefaults.defaultLeftColumnWidth
        }
        nonmutating set {
            let clamped = min(max(newValue, LayoutDefaults.minLeftColumnWidth), LayoutDefaults.maxLeftColumnWidth)
            userDefaults.set(clamped, forKey: LayoutDefaults.leftColumnWidthKey)
            userDefaults.synchronize()
        }
    }

    /// The saved playlist sort option, syncing composite option, field, and order keys.
    var sortOption: PlaylistSortOption {
        get {
            if let raw = userDefaults.string(forKey: LayoutDefaults.playlistSortOptionKey),
               let option = PlaylistSortOption(rawValue: raw) {
                return option
            }
            return .dateDescending
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: LayoutDefaults.playlistSortOptionKey)
            userDefaults.set(newValue.field.rawValue, forKey: LayoutDefaults.playlistSortFieldKey)
            userDefaults.set(newValue.order.rawValue, forKey: LayoutDefaults.playlistSortOrderKey)
            userDefaults.synchronize()
        }
    }

    /// The saved playlist view mode ("tree" or "flat").
    var viewMode: String {
        get {
            userDefaults.string(forKey: LayoutDefaults.playlistViewModeKey) ?? "tree"
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: LayoutDefaults.playlistViewModeKey)
            userDefaults.synchronize()
        }
    }

    /// Saves window size directly with width and height doubles.
    func saveWindowSize(width: Double, height: Double) {
        guard width >= LayoutDefaults.minWindowWidth && height >= LayoutDefaults.minWindowHeight else { return }
        userDefaults.set(width, forKey: LayoutDefaults.windowWidthKey)
        userDefaults.set(height, forKey: LayoutDefaults.windowHeightKey)
        userDefaults.synchronize()
    }

    /// Saves left column width directly.
    func saveLeftColumnWidth(_ width: Double) {
        let clamped = min(max(width, LayoutDefaults.minLeftColumnWidth), LayoutDefaults.maxLeftColumnWidth)
        userDefaults.set(clamped, forKey: LayoutDefaults.leftColumnWidthKey)
        userDefaults.synchronize()
    }

    /// Saves sort settings directly.
    func saveSortOption(_ option: PlaylistSortOption) {
        self.sortOption = option
    }

    /// Saves view mode directly.
    func saveViewMode(_ mode: String) {
        self.viewMode = mode
    }
}
