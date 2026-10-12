import Foundation

// MARK: - Conflict Policies

enum SongConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case overwrite = "Overwrite"
    case keepExisting = "Keep Existing"
    case rename = "Rename (Keep Both)"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .overwrite: "Replace existing presentation files in the target library."
        case .keepExisting: "Preserve the existing library files and skip copying."
        case .rename: "Keep both files by appending '(Imported)' to the imported file."
        }
    }
}

enum PlaylistConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case keepBoth = "Create New (Rename)"
    case overwrite = "Overwrite Existing"
    case skip = "Do Not Create"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .keepBoth: "Create a new playlist with '(Imported)' appended if a match exists."
        case .overwrite: "Replace the items in the existing playlist."
        case .skip: "Import presentation files only; do not create or modify any playlist."
        }
    }
}

enum GroupConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case useExisting = "Use Existing Group"
    case createNew = "Create New Group"
    case skip = "No Group (Root)"

    var id: String { rawValue }
}

// MARK: - Progress & Errors

struct ImportProgress: Sendable, Equatable {
    enum Phase: String, Sendable {
        case extracting = "Extracting package"
        case inspecting = "Reading manifest"
        case copying = "Importing presentations"
        case indexing = "Syncing with ProPresenter"
        case creatingPlaylist = "Updating playlist"
        case done = "Done"
    }

    var phase: Phase
    var message: String
    var fraction: Double?
}

typealias ImportProgressHandler = @Sendable (ImportProgress) -> Void

enum ImportError: LocalizedError {
    case invalidArchive(String)
    case manifestNotFound
    case decodingManifest(String)
    case staging(String)
    case libraryNotFound(String)
    case ditto(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail):
            "Invalid package archive: \(detail)"
        case .manifestNotFound:
            "This archive does not contain a valid ProPack manifest.json."
        case .decodingManifest(let detail):
            "Couldn't read manifest.json: \(detail)"
        case .staging(let detail):
            "Failed to prepare import staging: \(detail)"
        case .libraryNotFound(let name):
            "Target library '\(name)' could not be located on disk."
        case .ditto(let status, let message):
            "Archive extraction failed (exit \(status)): \(message.isEmpty ? "unknown error" : message)"
        }
    }
}

// MARK: - Models

struct ImportPresentationItem: Identifiable, Sendable {
    let id: String
    let name: String
    let originalPackagePath: String
    let stagedFileURL: URL
    let defaultTargetFileName: String
    let slideCount: Int
    let groupNames: [String]
}

struct ImportMediaItem: Identifiable, Sendable {
    let id: String
    let filename: String
    let stagedFileURL: URL
    let sizeBytes: Int64
    let kind: MediaAsset.Kind

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct ImportPackage: Sendable {
    let archiveURL: URL
    let stagingDirectory: URL
    let manifest: Manifest
    let playlistName: String
    let presentations: [ImportPresentationItem]
    let media: [ImportMediaItem]

    var totalMediaSizeBytes: Int64 { media.reduce(0) { $0 + $1.sizeBytes } }
    var formattedMediaSize: String { ByteCountFormatter.string(fromByteCount: totalMediaSizeBytes, countStyle: .file) }
}

struct ImportResult: Sendable {
    let importedSongsCount: Int
    let skippedSongsCount: Int
    let renamedSongsCount: Int
    let importedMediaCount: Int
    let playlistName: String?
    let targetLibraryName: String
}

// MARK: - Service

struct ImportService: Sendable {
    let client: ProPresenterClient?

    init(client: ProPresenterClient? = nil) {
        self.client = client
    }

    static var stagingBaseDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ProPack", directoryHint: .isDirectory)
            .appending(path: "ImportStaging", directoryHint: .isDirectory)
    }

    static func purgeAllStagingDirectories() {
        try? FileManager.default.removeItem(at: stagingBaseDirectory)
    }

    // MARK: Inspect Package

    /// Extracts the package archive to a temp directory and parses `manifest.json`.
    func inspect(archiveURL: URL, progress: ImportProgressHandler? = nil) async throws -> ImportPackage {
        progress?(.init(phase: .extracting, message: "Extracting \(archiveURL.lastPathComponent)…", fraction: nil))

        let fm = FileManager.default
        let stagingDir = Self.stagingBaseDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let extractOutput = try await ProcessRunner.run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, stagingDir.path]
        )
        guard extractOutput.status == 0 else {
            try? fm.removeItem(at: stagingDir)
            throw ImportError.ditto(status: extractOutput.status, message: extractOutput.stderrString)
        }

        progress?(.init(phase: .inspecting, message: "Reading package manifest…", fraction: nil))

        // Locate manifest.json anywhere in extracted hierarchy
        guard let manifestURL = findManifest(in: stagingDir) else {
            try? fm.removeItem(at: stagingDir)
            throw ImportError.manifestNotFound
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let manifest: Manifest
        do {
            manifest = try decoder.decode(Manifest.self, from: manifestData)
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw ImportError.decodingManifest(error.localizedDescription)
        }

        let packageRootDir = manifestURL.deletingLastPathComponent()

        // Match presentation files from manifest items
        var presentationItems: [ImportPresentationItem] = []
        for item in manifest.items where item.type == "presentation" {
            guard let fileInfo = item.file else { continue }
            let stagedFile = packageRootDir.appending(path: fileInfo.packagePath)
            if fm.fileExists(atPath: stagedFile.path) {
                let slideCount = item.groups?.reduce(0) { $0 + $1.slideCount } ?? 0
                let groupNames = item.groups?.compactMap { $0.name } ?? []
                presentationItems.append(ImportPresentationItem(
                    id: item.presentationUuid ?? UUID().uuidString,
                    name: item.name,
                    originalPackagePath: fileInfo.packagePath,
                    stagedFileURL: stagedFile,
                    defaultTargetFileName: stagedFile.lastPathComponent,
                    slideCount: slideCount,
                    groupNames: groupNames
                ))
            }
        }

        var mediaItems: [ImportMediaItem] = []
        if let manifestMedia = manifest.media {
            for mediaInfo in manifestMedia {
                let staged = packageRootDir.appending(path: mediaInfo.packagePath)
                if fm.fileExists(atPath: staged.path) {
                    let kind = MediaAsset.Kind.from(extension: staged.pathExtension)
                    mediaItems.append(ImportMediaItem(
                        id: mediaInfo.sha256,
                        filename: staged.lastPathComponent,
                        stagedFileURL: staged,
                        sizeBytes: Int64(mediaInfo.sizeBytes),
                        kind: kind
                    ))
                }
            }
        } else {
            let mediaFolder = packageRootDir.appending(path: "Media", directoryHint: .isDirectory)
            if let entries = try? fm.contentsOfDirectory(at: mediaFolder, includingPropertiesForKeys: [.fileSizeKey]) {
                for staged in entries {
                    let size = (try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    let kind = MediaAsset.Kind.from(extension: staged.pathExtension)
                    mediaItems.append(ImportMediaItem(
                        id: staged.lastPathComponent,
                        filename: staged.lastPathComponent,
                        stagedFileURL: staged,
                        sizeBytes: size,
                        kind: kind
                    ))
                }
            }
        }

        return ImportPackage(
            archiveURL: archiveURL,
            stagingDirectory: stagingDir,
            manifest: manifest,
            playlistName: manifest.playlist.name,
            presentations: presentationItems,
            media: mediaItems
        )
    }

    // MARK: Execute Import

    func executeImport(
        package: ImportPackage,
        targetLibraryURL: URL,
        songConflictPolicy: SongConflictPolicy,
        playlistConflictPolicy: PlaylistConflictPolicy,
        targetGroupName: String? = nil,
        groupConflictPolicy: GroupConflictPolicy = .useExisting,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: package.stagingDirectory) }

        try fm.createDirectory(at: targetLibraryURL, withIntermediateDirectories: true)

        var importedCount = 0
        var skippedCount = 0
        var renamedCount = 0
        var installedPresentationFiles: [String: URL] = [:] // presentationUUID -> installed URL

        // 0. Copy media assets if present
        var importedMediaCount = 0
        if !package.media.isEmpty {
            let mediaTargetDir = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Documents/ProPresenter/Media", directoryHint: .isDirectory)
            try? fm.createDirectory(at: mediaTargetDir, withIntermediateDirectories: true)
            for mediaItem in package.media {
                let dest = mediaTargetDir.appending(path: mediaItem.filename)
                if !fm.fileExists(atPath: dest.path) {
                    if (try? fm.copyItem(at: mediaItem.stagedFileURL, to: dest)) != nil {
                        importedMediaCount += 1
                    }
                }
            }
        }

        // 1. Copy presentation files into target library
        let totalPresentations = max(package.presentations.count, 1)
        for (index, presentation) in package.presentations.enumerated() {
            try Task.checkCancellation()
            progress?(.init(
                phase: .copying,
                message: "Importing \(presentation.name)…",
                fraction: Double(index) / Double(totalPresentations)
            ))

            let destinationURL = targetLibraryURL.appending(path: presentation.defaultTargetFileName)
            let fileExists = fm.fileExists(atPath: destinationURL.path)

            var finalDestination = destinationURL
            if fileExists {
                switch songConflictPolicy {
                case .overwrite:
                    try? fm.removeItem(at: destinationURL)
                    try fm.copyItem(at: presentation.stagedFileURL, to: destinationURL)
                    importedCount += 1
                case .keepExisting:
                    skippedCount += 1
                case .rename:
                    finalDestination = Self.uniqueFileURL(for: destinationURL)
                    try fm.copyItem(at: presentation.stagedFileURL, to: finalDestination)
                    renamedCount += 1
                }
            } else {
                try fm.copyItem(at: presentation.stagedFileURL, to: destinationURL)
                importedCount += 1
            }

            installedPresentationFiles[presentation.id] = finalDestination
        }

        // 2. Playlist creation / updating via ProPresenter REST API
        var finalPlaylistName: String?
        if let client, playlistConflictPolicy != .skip {
            progress?(.init(phase: .indexing, message: "Syncing with ProPresenter library…", fraction: nil))

            // Allow ProPresenter's file monitor up to 1.5 seconds to pick up the new files
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            progress?(.init(phase: .creatingPlaylist, message: "Creating playlist…", fraction: nil))

            // Query existing playlists
            let existingPlaylists = (try? await client.playlists()) ?? []
            let basePlaylistName = package.playlistName
            let existingMatch = PPPlaylistNode.findByName(basePlaylistName, in: existingPlaylists)

            let targetPlaylistID: String
            if let existing = existingMatch, playlistConflictPolicy == .overwrite {
                targetPlaylistID = existing.id
                finalPlaylistName = existing.name
            } else {
                // Determine unique playlist name if keeping both
                let uniqueName: String
                if existingMatch != nil && playlistConflictPolicy == .keepBoth {
                    uniqueName = Self.uniquePlaylistName(for: basePlaylistName, existing: existingPlaylists)
                } else {
                    uniqueName = basePlaylistName
                }

                // If group is requested, find or create the group
                var parentGroupID: String?
                if let targetGroupName, !targetGroupName.isEmpty {
                    let existingGroup = existingPlaylists.first { $0.isGroup && $0.name.localizedCaseInsensitiveCompare(targetGroupName) == .orderedSame }
                    if let existingGroup, groupConflictPolicy == .useExisting {
                        parentGroupID = existingGroup.id
                    } else if groupConflictPolicy == .createNew || (existingGroup == nil && groupConflictPolicy != .skip) {
                        let groupName = (existingGroup != nil) ? "\(targetGroupName) (Imported)" : targetGroupName
                        if let createdGroup = try? await client.createPlaylist(name: groupName, type: "group") {
                            parentGroupID = createdGroup.id
                        }
                    }
                }

                _ = parentGroupID // ProPresenter adds newly created playlists to current workspace
                let createdPlaylist = try await client.createPlaylist(name: uniqueName, type: "playlist")
                targetPlaylistID = createdPlaylist.id
                finalPlaylistName = uniqueName
            }

            // Map manifest items to PPPlaylistItemPayload
            // Fetch updated library items to resolve newly assigned UUIDs if any
            let libraryItems = await Self.fetchAllLibraryItems(client: client)

            var payloads: [PPPlaylistItemPayload] = []
            for (index, item) in package.manifest.items.enumerated() {
                let itemName = item.name
                let itemType = item.type

                var presentationUUID = item.presentationUuid ?? ""
                // If ProPresenter re-indexed the presentation under a fresh UUID, match by name
                if let matched = libraryItems.first(where: { $0.name.localizedCaseInsensitiveCompare(itemName) == .orderedSame }) {
                    presentationUUID = matched.uuid
                }

                let arrangementName = item.arrangement?.name ?? ""
                let arrangementUUID = item.arrangement?.uuid ?? ""

                let payload = PPPlaylistItemPayload(
                    id: .init(uuid: UUID().uuidString, name: itemName, index: index),
                    type: itemType,
                    isHidden: item.isHidden,
                    isPco: false,
                    presentationInfo: (itemType == "presentation") ? .init(
                        presentationUuid: presentationUUID,
                        arrangementName: arrangementName,
                        arrangementUuid: arrangementUUID
                    ) : nil,
                    destination: "presentation",
                    targetUuid: ""
                )
                payloads.append(payload)
            }

            try await client.updatePlaylistItems(id: targetPlaylistID, items: payloads)
        }

        progress?(.init(phase: .done, message: "Import complete", fraction: 1))

        return ImportResult(
            importedSongsCount: importedCount,
            skippedSongsCount: skippedCount,
            renamedSongsCount: renamedCount,
            importedMediaCount: importedMediaCount,
            playlistName: finalPlaylistName,
            targetLibraryName: targetLibraryURL.lastPathComponent
        )
    }

    // MARK: - Helpers

    private func findManifest(in directory: URL) -> URL? {
        let fm = FileManager.default
        let direct = directory.appending(path: ExportService.manifestFileName)
        if fm.fileExists(atPath: direct.path) { return direct }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == ExportService.manifestFileName {
                return url
            }
        }
        return nil
    }

    private static func fetchAllLibraryItems(client: ProPresenterClient) async -> [PPLibraryItem] {
        guard let libs = try? await client.libraries() else { return [] }
        var all: [PPLibraryItem] = []
        for lib in libs {
            if let items = try? await client.libraryItems(id: lib.uuid) {
                all.append(contentsOf: items)
            }
        }
        return all
    }

    static func uniqueFileURL(for destination: URL) -> URL {
        let dir = destination.deletingLastPathComponent()
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        let fm = FileManager.default

        var candidate = dir.appending(path: "\(base) (Imported).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appending(path: "\(base) (Imported \(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }

    static func uniquePlaylistName(for base: String, existing: [PPPlaylistNode]) -> String {
        let allLeaves = PPPlaylistNode.leaves(of: existing)
        var candidate = "\(base) (Imported)"
        var counter = 2
        while allLeaves.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) (Imported \(counter))"
            counter += 1
        }
        return candidate
    }
}

private extension PPPlaylistNode {
    static func findByName(_ name: String, in nodes: [PPPlaylistNode]) -> PPPlaylistNode? {
        for node in nodes {
            if !node.isGroup && node.name.localizedCaseInsensitiveCompare(name) == .orderedSame {
                return node
            }
            if let hit = findByName(name, in: node.children ?? []) {
                return hit
            }
        }
        return nil
    }
}
