import CoreText
import Foundation

// MARK: - Theme Asset

public struct ThemeAsset: Identifiable, Hashable, Sendable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let filename: String
    /// Path relative to the enclosing `Themes` folder (e.g. `Livestream/Lower Thirds` or `Worship.proTheme`).
    public let relativePath: String
    public let themeName: String
    public let sizeBytes: Int64

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Font Asset

public struct FontAsset: Identifiable, Hashable, Sendable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let filename: String
    public let fontName: String
    public let sizeBytes: Int64

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Theme Locator

enum ThemeLocator {
    /// Discovers candidate ProPresenter `Themes` directories from active library roots and configured workspaces.
    static func defaultThemeRoots(forLibraryRoots libraryRoots: [URL] = []) -> [URL] {
        var candidates: [URL] = []

        // Infer sibling `Themes` folder from any discovered or manual `Libraries` folder.
        for libRoot in libraryRoots {
            var dir = libRoot.standardizedFileURL
            while dir.pathComponents.count > 1 {
                if dir.lastPathComponent == "Libraries" {
                    let proRoot = dir.deletingLastPathComponent()
                    candidates.append(proRoot.appending(path: "Themes", directoryHint: .isDirectory))
                    break
                }
                dir = dir.deletingLastPathComponent()
            }
            // Also check sibling Themes folder directly next to the library root
            candidates.append(libRoot.deletingLastPathComponent().appending(path: "Themes", directoryHint: .isDirectory))
        }

        // Add `Themes` directories from all detected ProPresenter workspaces on this machine
        for workspace in LibraryLocator.detectedWorkspaceDirectories {
            candidates.append(workspace.appending(path: "Themes", directoryHint: .isDirectory))
        }

        return LibraryLocator.normalizedRoots(candidates)
    }

    /// Infers the target `Themes` directory corresponding to a target library folder on import.
    static func targetThemesDirectory(forTargetLibraryURL targetLibraryURL: URL) -> URL {
        let workspace = LibraryLocator.workspaceDirectory(forTargetLibraryURL: targetLibraryURL)
        return workspace.appending(path: "Themes", directoryHint: .isDirectory)
    }

    /// Filters Audience Looks to the currently active Look plus any saved Looks referenced by slide cues in `proURLs`.
    static func relevantAudienceLooks(
        currentLook: PPLookSummary?,
        allLooks: [PPLookSummary],
        inProFiles proURLs: [URL]
    ) -> [PPLookSummary] {
        var results: [PPLookSummary] = []
        var seenIDs = Set<String>()

        if let currentLook {
            results.append(currentLook)
            seenIDs.insert(currentLook.id.lowercased())
        }

        guard !allLooks.isEmpty, !proURLs.isEmpty else { return results }

        let proDataBlobs = proURLs.compactMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        guard !proDataBlobs.isEmpty else { return results }

        for look in allLooks {
            let lowerID = look.id.lowercased()
            guard !seenIDs.contains(lowerID) else { continue }

            let matchesUUID = look.id.count >= 4 && proDataBlobs.contains { dataContainsASCII(look.id, in: $0) }
            let matchesName = look.name.count >= 3 && proDataBlobs.contains { dataContainsASCII(look.name, in: $0) }

            if matchesUUID || matchesName {
                seenIDs.insert(lowerID)
                results.append(look)
            }
        }

        return results
    }

    /// Resolves Theme files on disk that are used by the active/referenced Audience Looks or directly by `.pro` files.
    static func findReferencedThemes(
        inProFiles proURLs: [URL],
        audienceLooks: [PPLookSummary],
        themeRoots: [URL]
    ) -> [ThemeAsset] {
        let normalizedRoots = LibraryLocator.normalizedRoots(themeRoots)
        let availableThemeFiles = enumerateThemeFiles(under: normalizedRoots)

        var matchedAssets: [URL: ThemeAsset] = [:]

        let proDataBlobs = proURLs.compactMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }

        // 1. Check explicit theme paths in .pro files (e.g. `/.../Themes/Lower Thirds` or `Custom.proTheme`)
        for data in proDataBlobs {
            for candidatePath in extractPotentialThemePaths(from: data) {
                if let resolved = resolveExplicitThemePath(candidatePath, roots: normalizedRoots, availableFiles: availableThemeFiles) {
                    addThemeAsset(for: resolved, roots: normalizedRoots, into: &matchedAssets)
                }
            }
        }

        guard !availableThemeFiles.isEmpty else {
            return sortedAssets(matchedAssets)
        }

        // Preload theme file contents for fast matching
        let themeFileData: [URL: Data] = Dictionary(uniqueKeysWithValues: availableThemeFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return (url, data)
        })

        // 2. Match themes referenced by Audience Looks
        let lookThemeRefs = audienceLooks.flatMap(\.referencedThemes)
        for themeRef in lookThemeRefs {
            let refUUID = themeRef.uuid.trimmingCharacters(in: .whitespacesAndNewlines)
            let refName = themeRef.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Sometimes ProPresenter formats a theme slide name as "<ThemeName>/<SlideName>" or "<ThemeName> - <SlideName>"
            let primaryName = refName.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? refName

            var matchedCurrentRef = false

            for fileURL in availableThemeFiles {
                let fileName = fileURL.lastPathComponent
                let fileStem = fileURL.deletingPathExtension().lastPathComponent
                let themeDisplay = logicalThemeName(for: fileURL)

                // Match by filename, stem, or enclosing theme folder name (for `Themes/<ThemeName>/Theme`)
                if !refName.isEmpty && (
                    fileName.localizedCaseInsensitiveCompare(refName) == .orderedSame ||
                    fileStem.localizedCaseInsensitiveCompare(refName) == .orderedSame ||
                    themeDisplay.localizedCaseInsensitiveCompare(refName) == .orderedSame ||
                    fileName.localizedCaseInsensitiveCompare(primaryName) == .orderedSame ||
                    fileStem.localizedCaseInsensitiveCompare(primaryName) == .orderedSame ||
                    themeDisplay.localizedCaseInsensitiveCompare(primaryName) == .orderedSame
                ) {
                    addThemeAsset(for: fileURL, preferredName: themeDisplay, roots: normalizedRoots, into: &matchedAssets)
                    matchedCurrentRef = true
                    continue
                }

                // Match by UUID inside the theme file's protobuf data (covers both Theme UUID and Theme Slide UUID)
                if refUUID.count >= 4, let data = themeFileData[fileURL], dataContainsASCII(refUUID, in: data) {
                    addThemeAsset(for: fileURL, preferredName: themeDisplay, roots: normalizedRoots, into: &matchedAssets)
                    matchedCurrentRef = true
                    continue
                }
            }

            // Fallback: if neither filename nor UUID matched, check if the theme name appears inside the theme file
            if !matchedCurrentRef, primaryName.count >= 3 {
                for fileURL in availableThemeFiles {
                    let themeDisplay = logicalThemeName(for: fileURL)
                    if let data = themeFileData[fileURL], dataContainsASCII(primaryName, in: data) {
                        addThemeAsset(for: fileURL, preferredName: themeDisplay, roots: normalizedRoots, into: &matchedAssets)
                    }
                }
            }
        }

        // 3. Check if any theme file in `Themes/` is directly referenced inside any `.pro` file
        if !proDataBlobs.isEmpty {
            for fileURL in availableThemeFiles where matchedAssets[fileURL.standardizedFileURL] == nil {
                let fileStem = fileURL.deletingPathExtension().lastPathComponent
                let fileName = fileURL.lastPathComponent
                let themeDisplay = logicalThemeName(for: fileURL)

                // Check if `Themes/<fileName>` or `Themes/<themeDisplay>` or the theme's internal UUIDs appear in the .pro data
                let referencedByName = themeDisplay.count >= 3 && proDataBlobs.contains {
                    dataContainsASCII("Themes/\(fileName)", in: $0) ||
                    dataContainsASCII("Themes/\(fileStem)", in: $0) ||
                    dataContainsASCII("Themes/\(themeDisplay)", in: $0) ||
                    dataContainsASCII("\(themeDisplay).proTheme", in: $0)
                }

                var referencedByUUID = false
                if !referencedByName, let tData = themeFileData[fileURL] {
                    let themeUUIDs = extractUUIDStrings(from: tData)
                    if !themeUUIDs.isEmpty {
                        referencedByUUID = themeUUIDs.contains { uuid in
                            proDataBlobs.contains { dataContainsASCII(uuid, in: $0) }
                        }
                    }
                }

                if referencedByName || referencedByUUID {
                    addThemeAsset(for: fileURL, preferredName: themeDisplay, roots: normalizedRoots, into: &matchedAssets)
                }
            }
        }

        return sortedAssets(matchedAssets)
    }

    // MARK: - Theme Helpers

    /// Returns the human-readable Theme name for a theme file URL (handling `Themes/<ThemeName>/Theme` in ProPresenter 22+).
    static func logicalThemeName(for fileURL: URL) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        if stem.localizedCaseInsensitiveCompare("Theme") == .orderedSame {
            let parentName = fileURL.deletingLastPathComponent().lastPathComponent
            if !parentName.isEmpty && parentName.localizedCaseInsensitiveCompare("Themes") != .orderedSame {
                return parentName
            }
        }
        return stem
    }

    static func extractPotentialThemePaths(from data: Data) -> [String] {
        guard let ascii = String(data: data, encoding: .isoLatin1) else { return [] }
        var results: [String] = []

        let patterns = [
            #"(?:/[^\x00-\x1F\x7F-\xFF]+|\b[a-zA-Z0-9_\- ]+)\.(?:proTheme|protheme|protemplate)\b"#,
            #"(?:/[^\x00-\x1F\x7F-\xFF]*/Themes/[a-zA-Z0-9_\- ./]+)"#
        ]
        let nsString = ascii as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: ascii, range: NSRange(location: 0, length: nsString.length)) {
                let candidate = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    results.append(candidate)
                }
            }
        }
        return results
    }

    private static func resolveExplicitThemePath(_ candidate: String, roots: [URL], availableFiles: [URL]) -> URL? {
        let fm = FileManager.default
        let expanded = (candidate as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if expanded.hasPrefix("/") && fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue {
            return URL(fileURLWithPath: expanded)
        }
        let name = URL(fileURLWithPath: candidate).lastPathComponent
        let stem = URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent
        return availableFiles.first {
            let logical = logicalThemeName(for: $0)
            return $0.lastPathComponent.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(stem) == .orderedSame ||
                logical.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                logical.localizedCaseInsensitiveCompare(stem) == .orderedSame
        }
    }

    private static func enumerateThemeFiles(under roots: [URL]) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                // Skip embedded media inside `Themes/<ThemeName>/Assets/`
                if url.pathComponents.contains(where: { $0.localizedCaseInsensitiveCompare("Assets") == .orderedSame }) {
                    continue
                }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    files.append(url)
                }
            }
        }
        return files
    }

    private static func addThemeAsset(
        for fileURL: URL,
        preferredName: String? = nil,
        roots: [URL],
        into dict: inout [URL: ThemeAsset]
    ) {
        let standardized = fileURL.standardizedFileURL
        guard dict[standardized] == nil else { return }
        let size = (try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let relPath = relativePath(of: standardized, roots: roots)
        let fallbackName = logicalThemeName(for: standardized)
        let displayName = (preferredName?.isEmpty == false) ? preferredName! : fallbackName
        dict[standardized] = ThemeAsset(
            url: standardized,
            filename: standardized.lastPathComponent,
            relativePath: relPath,
            themeName: displayName,
            sizeBytes: size
        )
    }

    private static func relativePath(of file: URL, roots: [URL]) -> String {
        let filePath = file.resolvingSymlinksInPath().path
        for root in roots {
            let rootPath = root.resolvingSymlinksInPath().path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if filePath.hasPrefix(prefix) {
                return String(filePath.dropFirst(prefix.count))
            }
        }
        return file.lastPathComponent
    }

    private static func extractUUIDStrings(from data: Data) -> [String] {
        guard let ascii = String(data: data, encoding: .isoLatin1) else { return [] }
        let pattern = #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = ascii as NSString
        var seen = Set<String>()
        var results: [String] = []
        for match in regex.matches(in: ascii, range: NSRange(location: 0, length: ns.length)) {
            let uuid = ns.substring(with: match.range)
            if seen.insert(uuid.lowercased()).inserted {
                results.append(uuid)
            }
        }
        return results
    }

    private static func dataContainsASCII(_ needle: String, in data: Data) -> Bool {
        for variant in Set([needle, needle.uppercased(), needle.lowercased()]) {
            if let needleData = variant.data(using: .utf8), !needleData.isEmpty, data.range(of: needleData) != nil {
                return true
            }
        }
        return false
    }

    private static func sortedAssets(_ dict: [URL: ThemeAsset]) -> [ThemeAsset] {
        Array(dict.values).sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }
}

// MARK: - Font Locator

public enum FontLocator {
    public static let supportedFontExtensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    /// User and local font directories on macOS (excludes `/System/Library/Fonts` built-in system fonts).
    public static var defaultFontRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Fonts", directoryHint: .isDirectory),
            URL(fileURLWithPath: "/Library/Fonts", isDirectory: true)
        ]
    }

    /// Default destination folder where imported fonts are installed for the current user.
    public static var userFontsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Fonts", directoryHint: .isDirectory)
    }

    /// Extracts referenced custom font files from `.pro` presentation files and Theme files.
    public static func findReferencedFonts(
        inFiles fileURLs: [URL],
        fontRoots: [URL] = defaultFontRoots,
        allowCoreTextLookup: Bool = true
    ) -> [FontAsset] {
        guard !fileURLs.isEmpty else { return [] }

        let fontIndex = FontDirectoryIndex(roots: fontRoots)
        var foundAssets: [URL: FontAsset] = [:]

        for fileURL in fileURLs {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { continue }

            // 1. Extract font names from RTF `\fonttbl`, PostScript names, and explicit `.ttf`/`.otf` strings
            var candidateNames = extractFontNames(from: data)

            // 2. Also check if any font file in `fontRoots` has its family/PostScript/stem name directly in the binary data
            for (knownName, _) in fontIndex.byNormalizedName where knownName.count >= 4 {
                if dataContainsCaseInsensitiveASCII(knownName, in: data) {
                    candidateNames.append(knownName)
                }
            }

            for candidate in candidateNames {
                if let resolved = resolveFont(named: candidate, index: fontIndex, allowCoreTextLookup: allowCoreTextLookup) {
                    let standardized = resolved.url.standardizedFileURL
                    if foundAssets[standardized] == nil {
                        let size = (try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                        foundAssets[standardized] = FontAsset(
                            url: standardized,
                            filename: standardized.lastPathComponent,
                            fontName: resolved.displayName,
                            sizeBytes: size
                        )
                    }
                }
            }
        }

        return Array(foundAssets.values).sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    /// Extracts font names and font filenames referenced in ProPresenter protobuf / RTF data.
    public static func extractFontNames(from data: Data) -> [String] {
        guard let ascii = String(data: data, encoding: .isoLatin1) else { return [] }
        let nsString = ascii as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        var ordered: [String] = []
        var seen = Set<String>()

        func addCandidate(_ raw: String) {
            let trimmed = raw
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\";{}")))
            guard trimmed.count >= 2, !trimmed.hasPrefix(".") else { return }
            if seen.insert(trimmed.lowercased()).inserted {
                ordered.append(trimmed)
            }
        }

        // 1. RTF font table entries: e.g. `{\f0\fnil\fcharset0 Montserrat-Bold;}` or `\f1\fswiss Helvetica Neue;`
        let rtfPattern = #"\\f\d+(?:\\[a-zA-Z0-9]+)*\s+([A-Za-z0-9][A-Za-z0-9_\- .]+?);[\}\\]"#
        if let regex = try? NSRegularExpression(pattern: rtfPattern) {
            for match in regex.matches(in: ascii, range: fullRange) where match.numberOfRanges > 1 {
                addCandidate(nsString.substring(with: match.range(at: 1)))
            }
        }

        // 2. Explicit font file names or paths: e.g. `Montserrat-Bold.ttf`, `CustomFont.otf`
        let filePattern = #"(?:/[^\x00-\x1F\x7F-\xFF]+|\b[a-zA-Z0-9_\- ]+)\.(?:ttf|otf|ttc|dfont)\b"#
        if let regex = try? NSRegularExpression(pattern: filePattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: ascii, range: fullRange) {
                addCandidate(nsString.substring(with: match.range))
            }
        }

        // 3. PostScript-style font names in protobuf `rv.data.Font`: e.g. `Montserrat-Bold`, `BebasNeue-Regular`
        let psPattern = #"\b[A-Za-z][A-Za-z0-9]{2,30}-(?:Regular|Bold|Italic|BoldItalic|Light|Medium|SemiBold|DemiBold|ExtraBold|ExtraLight|Black|Thin|Heavy|Condensed|Oblique|Roman|Book|Ultra)[A-Za-z0-9]*\b"#
        if let regex = try? NSRegularExpression(pattern: psPattern) {
            for match in regex.matches(in: ascii, range: fullRange) {
                addCandidate(nsString.substring(with: match.range))
            }
        }

        return ordered
    }

    /// Installs a font file into the target fonts directory (`~/Library/Fonts` by default) and registers it with CoreText.
    @discardableResult
    public static func installFont(from stagedURL: URL, to targetDirectory: URL = userFontsDirectory) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let destination = targetDirectory.appending(path: stagedURL.lastPathComponent)

        var didCopy = false
        if !fm.fileExists(atPath: destination.path) {
            if (try? fm.copyItem(at: stagedURL, to: destination)) != nil {
                didCopy = true
            }
        }
        // Register font with CoreText for immediate availability in the user session
        CTFontManagerRegisterFontsForURL(destination as CFURL, .user, nil)
        return didCopy
    }

    // MARK: - Internal Resolution

    private struct ResolvedFont {
        let url: URL
        let displayName: String
    }

    private struct FontDirectoryIndex {
        /// Maps lowercased name variants (filename, stem, PostScript name, family name) to font file URL.
        var byNormalizedName: [String: (url: URL, displayName: String)] = [:]

        init(roots: [URL]) {
            let fm = FileManager.default
            for root in roots {
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    let ext = url.pathExtension.lowercased()
                    guard FontLocator.supportedFontExtensions.contains(ext) else { continue }
                    guard !FontLocator.isSystemFontURL(url) else { continue }

                    let filename = url.lastPathComponent
                    let stem = url.deletingPathExtension().lastPathComponent
                    register(key: filename, url: url, displayName: stem)
                    register(key: stem, url: url, displayName: stem)
                    register(key: Self.compactKey(stem), url: url, displayName: stem)

                    if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
                        for desc in descriptors {
                            let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
                            let familyName = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute) as? String
                            let dispName = CTFontDescriptorCopyAttribute(desc, kCTFontDisplayNameAttribute) as? String
                            let preferred = dispName ?? familyName ?? psName ?? stem
                            if let psName {
                                register(key: psName, url: url, displayName: preferred)
                                register(key: Self.compactKey(psName), url: url, displayName: preferred)
                            }
                            if let familyName {
                                register(key: familyName, url: url, displayName: preferred)
                                register(key: Self.compactKey(familyName), url: url, displayName: preferred)
                            }
                            if let dispName {
                                register(key: dispName, url: url, displayName: preferred)
                            }
                        }
                    }
                }
            }
        }

        private mutating func register(key: String, url: URL, displayName: String) {
            let lower = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty else { return }
            if byNormalizedName[lower] == nil {
                byNormalizedName[lower] = (url, displayName)
            }
        }

        static func compactKey(_ name: String) -> String {
            name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        }

        func lookup(_ candidate: String) -> (url: URL, displayName: String)? {
            let lower = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let hit = byNormalizedName[lower] { return hit }
            let fileName = URL(fileURLWithPath: candidate).lastPathComponent.lowercased()
            if let hit = byNormalizedName[fileName] { return hit }
            let stem = URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent.lowercased()
            if let hit = byNormalizedName[stem] { return hit }
            let compact = Self.compactKey(stem)
            return byNormalizedName[compact]
        }
    }

    private static func resolveFont(
        named candidate: String,
        index: FontDirectoryIndex,
        allowCoreTextLookup: Bool
    ) -> ResolvedFont? {
        let fm = FileManager.default
        let expanded = (candidate as NSString).expandingTildeInPath
        if expanded.hasPrefix("/"), fm.fileExists(atPath: expanded) {
            let url = URL(fileURLWithPath: expanded)
            if supportedFontExtensions.contains(url.pathExtension.lowercased()), !isSystemFontURL(url) {
                return ResolvedFont(url: url, displayName: url.deletingPathExtension().lastPathComponent)
            }
        }

        if let indexed = index.lookup(candidate) {
            return ResolvedFont(url: indexed.url, displayName: indexed.displayName)
        }

        guard allowCoreTextLookup else { return nil }
        let cleanName = URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent
        let descriptor = CTFontDescriptorCreateWithNameAndSize(cleanName as CFString, 12.0)
        if let fontURL = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
           fm.fileExists(atPath: fontURL.path),
           !isSystemFontURL(fontURL) {
            // Verify that CoreText matched the requested font name rather than a fallback font
            let matchedPS = (CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String) ?? ""
            let matchedFamily = (CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String) ?? ""
            let reqCompact = FontDirectoryIndex.compactKey(cleanName)
            if FontDirectoryIndex.compactKey(matchedPS).contains(reqCompact) ||
               FontDirectoryIndex.compactKey(matchedFamily).contains(reqCompact) ||
               FontDirectoryIndex.compactKey(fontURL.deletingPathExtension().lastPathComponent).contains(reqCompact) {
                return ResolvedFont(url: fontURL, displayName: matchedFamily.isEmpty ? cleanName : matchedFamily)
            }
        }

        return nil
    }

    /// Returns `true` if the font lives inside macOS's immutable `/System/Library/` hierarchy.
    public static func isSystemFontURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/System/Library/")
    }

    private static func dataContainsCaseInsensitiveASCII(_ lowerKey: String, in data: Data) -> Bool {
        if let utf8 = lowerKey.data(using: .utf8), data.range(of: utf8) != nil {
            return true
        }
        if let ascii = String(data: data, encoding: .isoLatin1) {
            return ascii.range(of: lowerKey, options: .caseInsensitive) != nil
        }
        return false
    }
}
