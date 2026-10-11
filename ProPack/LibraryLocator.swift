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

    /// Well-known library locations (ProPresenter 7 default + legacy/App Support layout).
    static var defaultLibraryRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Documents/ProPresenter/Libraries", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/RenewedVision/ProPresenter/Libraries", directoryHint: .isDirectory),
        ]
    }

    /// Converts an API `presentation_path` (absolute path, `~` path, or `file://` URL) to a file URL.
    static func fileURL(fromAPIPath path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") { return URL(string: trimmed) }
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
