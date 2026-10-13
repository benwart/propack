import Foundation

/// How a `.pro` file was matched to a playlist presentation. Recorded in the manifest.
enum MatchMethod: String, Codable, Sendable {
    /// `presentation_path` returned by `GET /v1/presentation/{uuid}` exists on disk.
    case apiPath = "api_presentation_path"
    /// A file named `<presentation name>.pro` was found under a library root.
    case fileName = "file_name"
    /// The presentation UUID string was found inside the `.pro` (protobuf) file contents.
    case uuidScan = "uuid_content_scan"
}

/// Resolves presentations to `.pro` files on disk.
enum LibraryLocator {
    struct Request: Sendable {
        let presentationUUID: String
        let name: String
        let apiPath: String?
    }

    struct Match: Sendable {
        let url: URL
        let method: MatchMethod
    }

    /// Discovers ProPresenter Workspace ("Show Directory") roots configured on this Mac,
    /// ordered from highest priority (active workspace in ProPresenter preferences) to standard fallbacks.
    static var detectedWorkspaceDirectories: [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        // 1. Inspect ~/Library/Preferences/com.renewedvision.propresenter.plist
        let plistURL = home.appending(path: "Library/Preferences/com.renewedvision.propresenter.plist")
        if let plistData = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {

            // 1a. `userWorkspaces` JSON blob (ProPresenter 7.15+ / 22+)
            if let wsData = plist["userWorkspaces"] as? Data,
               let wsArray = try? JSONSerialization.jsonObject(with: wsData) as? [[String: Any]] {
                // Prioritize active workspaces first
                let sorted = wsArray.sorted { ($0["isActive"] as? Bool == true) && ($1["isActive"] as? Bool != true) }
                for entry in sorted {
                    if let urlString = entry["url"] as? String,
                       let url = fileURL(fromAPIPath: urlString) {
                        candidates.append(url)
                    }
                }
            }

            // 1b. `applicationShowDirectory` (custom or default Show/Support files directory)
            if let showDir = plist["applicationShowDirectory"] as? String,
               let url = fileURL(fromAPIPath: showDir) {
                candidates.append(url)
            }

            // 1c. `savedCurrentLibraryPlaylistURLKey` (parent of `Libraries`)
            if let savedLib = plist["savedCurrentLibraryPlaylistURLKey"] as? String,
               let libRoot = libraryRoot(forAPIPath: savedLib) {
                if libRoot.lastPathComponent == "Libraries" {
                    candidates.append(libRoot.deletingLastPathComponent())
                }
            }
        }

        // 2. Inspect ~/Library/Application Support/RenewedVision/ProPresenter/media-manager.toml
        let tomlURL = home.appending(path: "Library/Application Support/RenewedVision/ProPresenter/media-manager.toml")
        if let tomlContent = try? String(contentsOf: tomlURL, encoding: .utf8) {
            for line in tomlContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("path"),
                   let firstQuote = trimmed.firstIndex(of: "\""),
                   let lastQuote = trimmed.lastIndex(of: "\""),
                   firstQuote < lastQuote {
                    let pathStr = String(trimmed[trimmed.index(after: firstQuote)..<lastQuote])
                    if let url = fileURL(fromAPIPath: pathStr) {
                        candidates.append(url)
                    }
                }
            }
        }

        // 3. Enumerate any workspaces inside ~/Library/Application Support/RenewedVision/ProPresenter/UserWorkspaces
        let userWorkspacesRoot = home.appending(
            path: "Library/Application Support/RenewedVision/ProPresenter/UserWorkspaces",
            directoryHint: .isDirectory
        )
        candidates.append(userWorkspacesRoot.appending(path: "ProPresenter", directoryHint: .isDirectory))
        if let children = try? fm.contentsOfDirectory(at: userWorkspacesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for child in children {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                    candidates.append(child)
                }
            }
        }

        // 4. Standard default ProPresenter locations
        candidates.append(home.appending(path: "Documents/ProPresenter", directoryHint: .isDirectory))
        candidates.append(home.appending(path: "Library/Application Support/RenewedVision/ProPresenter", directoryHint: .isDirectory))

        // Deduplicate while preserving priority order (including existing or primary configured paths)
        var seen = Set<String>()
        var unique: [URL] = []
        for url in candidates {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if seen.insert(path).inserted {
                unique.append(url.standardizedFileURL)
            }
        }
        return unique
    }

    /// Returns the primary active ProPresenter Workspace directory on this machine.
    static var primaryWorkspaceDirectory: URL {
        let workspaces = detectedWorkspaceDirectories
        if let existing = workspaces.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }
        return workspaces.first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/ProPresenter", directoryHint: .isDirectory)
    }

    /// Returns the currently selected library directory recorded in ProPresenter's preferences, if it exists on disk.
    static var configuredActiveLibraryDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plistURL = home.appending(path: "Library/Preferences/com.renewedvision.propresenter.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let savedLib = plist["savedCurrentLibraryPlaylistURLKey"] as? String,
              let url = fileURL(fromAPIPath: savedLib) else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url.standardizedFileURL
    }

    /// Well-known and configured `Libraries` locations (ordered by active workspace priority).
    static var defaultLibraryRoots: [URL] {
        var roots: [URL] = []
        if let activeLib = configuredActiveLibraryDirectory,
           activeLib.deletingLastPathComponent().lastPathComponent == "Libraries" {
            roots.append(activeLib.deletingLastPathComponent())
        }
        for workspace in detectedWorkspaceDirectories {
            roots.append(workspace.appending(path: "Libraries", directoryHint: .isDirectory))
        }
        return roots
    }

    /// Resolves the enclosing ProPresenter Workspace directory for a given target library folder.
    /// Walks up from `targetLibraryURL` looking for `Libraries`; if not inside a `Libraries` folder,
    /// checks if the parent directory is a custom workspace or falls back to `primaryWorkspaceDirectory`.
    static func workspaceDirectory(forTargetLibraryURL targetLibraryURL: URL) -> URL {
        var dir = targetLibraryURL.standardizedFileURL
        while dir.pathComponents.count > 1 {
            if dir.lastPathComponent == "Libraries" {
                return dir.deletingLastPathComponent()
            }
            dir = dir.deletingLastPathComponent()
        }
        let parent = targetLibraryURL.standardizedFileURL.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if parent != home {
            return parent
        }
        return primaryWorkspaceDirectory
    }

    /// Queries the live ProPresenter API for a sample presentation's on-disk `presentation_path`
    /// to discover the active `Libraries` root and specific library folder on the running machine.
    static func discoverActiveLibraryFromAPI(client: ProPresenterClient) async -> (librariesRoot: URL, firstLibraryFolder: URL?)? {
        guard let libs = try? await client.libraries(), !libs.isEmpty else { return nil }
        for lib in libs {
            guard let items = try? await client.libraryItems(id: lib.uuid),
                  let firstItem = items.first,
                  let presentation = try? await client.presentation(uuid: firstItem.uuid),
                  let apiPath = presentation.presentationPath,
                  let fileURL = fileURL(fromAPIPath: apiPath) else {
                continue
            }
            let folderURL = fileURL.deletingLastPathComponent().standardizedFileURL
            let libRoot = libraryRoot(forAPIPath: apiPath)?.standardizedFileURL ?? folderURL
            return (librariesRoot: libRoot, firstLibraryFolder: folderURL)
        }
        return nil
    }

    /// Converts an API `presentation_path` (absolute path, `~` path, or `file://` URL) to a file URL.
    static func fileURL(fromAPIPath path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed) ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "")
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    /// Walks up from a `.pro` path to the enclosing `Libraries` folder (falls back to the file's folder).
    static func libraryRoot(forAPIPath path: String) -> URL? {
        guard let file = fileURL(fromAPIPath: path) else { return nil }
        var dir = file.deletingLastPathComponent()
        while dir.pathComponents.count > 1 {
            if dir.lastPathComponent == "Libraries" { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return file.deletingLastPathComponent()
    }

    /// Removes duplicate and non-existent roots, preserving order.
    static func normalizedRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.filter { url in
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
            return seen.insert(path).inserted
        }
    }

    // MARK: Resolution

    /// Synchronous and potentially slow (filesystem walk + content scan); call off the main actor.
    /// Returns matches keyed by presentation UUID.
    static func resolve(_ requests: [Request], roots: [URL]) -> [String: Match] {
        var matches: [String: Match] = [:]
        let fm = FileManager.default

        // 1. Exact path reported by ProPresenter.
        for request in requests {
            if let apiPath = request.apiPath,
               let url = fileURL(fromAPIPath: apiPath),
               fm.isReadableFile(atPath: url.path) {
                matches[request.presentationUUID] = Match(url: url, method: .apiPath)
            }
        }
        var pending = requests.filter { matches[$0.presentationUUID] == nil }
        guard !pending.isEmpty else { return matches }

        let files = proFiles(under: normalizedRoots(roots))
        let byStem = Dictionary(grouping: files) { $0.deletingPathExtension().lastPathComponent.lowercased() }

        // 2. File name == presentation name (disambiguated by UUID when there are duplicates).
        for request in pending {
            guard let candidates = byStem[request.name.lowercased()], !candidates.isEmpty else { continue }
            if candidates.count == 1 {
                matches[request.presentationUUID] = Match(url: candidates[0], method: .fileName)
            } else if let hit = candidates.first(where: { fileContains(uuid: request.presentationUUID, at: $0) }) {
                matches[request.presentationUUID] = Match(url: hit, method: .uuidScan)
            } else {
                matches[request.presentationUUID] = Match(url: candidates[0], method: .fileName)
            }
        }
        pending = pending.filter { matches[$0.presentationUUID] == nil }
        guard !pending.isEmpty else { return matches }

        // 3. Single pass over every .pro file looking for the remaining UUIDs in the protobuf bytes.
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            pending.removeAll { request in
                guard dataContains(uuid: request.presentationUUID, in: data) else { return false }
                matches[request.presentationUUID] = Match(url: file, method: .uuidScan)
                return true
            }
            if pending.isEmpty { break }
        }
        return matches
    }

    static func proFiles(under roots: [URL]) -> [URL] {
        var results: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension.lowercased() == "pro" { results.append(url) }
            }
        }
        return results
    }

    private static func fileContains(uuid: String, at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return dataContains(uuid: uuid, in: data)
    }

    /// `.pro` files store UUIDs as ASCII strings inside protobuf messages.
    private static func dataContains(uuid: String, in data: Data) -> Bool {
        for variant in Set([uuid.uppercased(), uuid.lowercased()]) where data.range(of: Data(variant.utf8)) != nil {
            return true
        }
        return false
    }
}
