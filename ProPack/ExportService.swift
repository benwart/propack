import CryptoKit
import Foundation

// MARK: - Plan

/// Everything known about a playlist before export: API metadata + resolved `.pro` files.
/// Produced by `ExportService.prepare` (also used to drive the UI preview).
struct ExportPlan: Sendable {
    struct Entry: Identifiable, Sendable {
        let item: PPPlaylistItem
        let presentation: PPPresentation?
        let fetchError: String?
        let match: LibraryLocator.Match?

        var id: String { item.id }
        var isPresentation: Bool { item.isPresentation }
        var groupCount: Int { presentation?.groups?.count ?? 0 }
    }

    let playlist: PPIdentifier
    let proPresenter: PPVersion?
    let entries: [Entry]
    let referencedMedia: [MediaAsset]
    let libraryRoots: [URL]
    /// Library folder inferred from an API `presentation_path`, if any.
    let discoveredLibraryRoot: URL?
    let preparedAt: Date

    init(
        playlist: PPIdentifier,
        proPresenter: PPVersion?,
        entries: [Entry],
        referencedMedia: [MediaAsset] = [],
        libraryRoots: [URL],
        discoveredLibraryRoot: URL?,
        preparedAt: Date
    ) {
        self.playlist = playlist
        self.proPresenter = proPresenter
        self.entries = entries
        self.referencedMedia = referencedMedia
        self.libraryRoots = libraryRoots
        self.discoveredLibraryRoot = discoveredLibraryRoot
        self.preparedAt = preparedAt
    }

    var presentationEntries: [Entry] { entries.filter(\.isPresentation) }
    var resolvedCount: Int { presentationEntries.filter { $0.match != nil }.count }
    var missingCount: Int { presentationEntries.count - resolvedCount }
    var totalMediaSizeBytes: Int64 { referencedMedia.reduce(0) { $0 + $1.sizeBytes } }
    var formattedMediaSize: String { ByteCountFormatter.string(fromByteCount: totalMediaSizeBytes, countStyle: .file) }
}

// MARK: - Progress

struct ExportProgress: Sendable, Equatable {
    enum Phase: String, Sendable {
        case fetching = "Fetching playlist"
        case resolving = "Locating .pro files"
        case staging = "Copying files"
        case compressing = "Compressing"
        case done = "Done"
    }

    var phase: Phase
    var message: String
    /// 0…1, or `nil` for indeterminate.
    var fraction: Double?
}

typealias ProgressHandler = @Sendable (ExportProgress) -> Void

// MARK: - Result / Errors

struct ExportResult: Sendable {
    let archiveURL: URL
    let includedFiles: Int
    let includedMediaFiles: Int
    let missingPresentations: [String]
}

enum ExportError: LocalizedError {
    case noPresentations
    case nothingResolved(missing: [String])
    case staging(String)
    case ditto(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .noPresentations:
            "This playlist doesn't contain any presentations."
        case .nothingResolved(let missing):
            "None of the \(missing.count) presentation file(s) could be found on disk. Choose your ProPresenter Libraries folder and try again."
        case .staging(let detail):
            "Couldn't prepare the export folder: \(detail)"
        case .ditto(let status, let message):
            "ditto failed (exit \(status)): \(message.isEmpty ? "unknown error" : message)"
        }
    }
}

// MARK: - Service

struct ExportService: Sendable {
    static let manifestFileName = "manifest.json"
    static let presentationsFolder = "Presentations"
    static let manifestFormatVersion = 1

    let client: ProPresenterClient
    /// Extra roots to search (user-picked folder first). Defaults are appended automatically.
    var additionalLibraryRoots: [URL] = []

    init(client: ProPresenterClient = ProPresenterClient(port: 0), additionalLibraryRoots: [URL] = []) {
        self.client = client
        self.additionalLibraryRoots = additionalLibraryRoots
    }

    // MARK: Prepare

    func prepare(playlistID: String, progress: ProgressHandler? = nil) async throws -> ExportPlan {
        progress?(.init(phase: .fetching, message: "Loading playlist…", fraction: nil))
        async let versionTask = try? client.version()
        let detail = try await client.playlist(id: playlistID)

        let presentationItems = detail.presentationItems
        let uniqueUUIDs = Array(Set(presentationItems.compactMap { $0.presentationInfo?.presentationUuid }))

        // Fetch each unique presentation (groups + presentation_path), a few at a time.
        var presentations: [String: PPPresentation] = [:]
        var fetchErrors: [String: String] = [:]
        try await withThrowingTaskGroup(of: (String, Result<PPPresentation, Error>).self) { group in
            var iterator = uniqueUUIDs.makeIterator()
            let maxConcurrent = 4
            for _ in 0..<maxConcurrent {
                guard let uuid = iterator.next() else { break }
                group.addTask { [client] in (uuid, await Result { try await client.presentation(uuid: uuid) }) }
            }
            var completed = 0
            while let (uuid, result) = try await group.next() {
                try Task.checkCancellation()
                completed += 1
                switch result {
                case .success(let presentation): presentations[uuid] = presentation
                case .failure(let error): fetchErrors[uuid] = error.localizedDescription
                }
                progress?(.init(
                    phase: .fetching,
                    message: "Fetched presentation \(completed) of \(uniqueUUIDs.count)",
                    fraction: Double(completed) / Double(max(uniqueUUIDs.count, 1))
                ))
                if let next = iterator.next() {
                    group.addTask { [client] in (next, await Result { try await client.presentation(uuid: next) }) }
                }
            }
        }

        // Library discovery: the first API path tells us where the active library lives.
        let discoveredRoot = presentations.values.lazy
            .compactMap(\.presentationPath)
            .compactMap(LibraryLocator.libraryRoot(forAPIPath:))
            .first
        let roots = LibraryLocator.normalizedRoots(
            additionalLibraryRoots + [discoveredRoot].compactMap { $0 } + LibraryLocator.defaultLibraryRoots
        )

        progress?(.init(phase: .resolving, message: "Locating .pro files…", fraction: nil))
        let requests = uniqueUUIDs.map { uuid in
            LibraryLocator.Request(
                presentationUUID: uuid,
                name: presentations[uuid]?.identifier.name
                    ?? presentationItems.first { $0.presentationInfo?.presentationUuid == uuid }?.name
                    ?? uuid,
                apiPath: presentations[uuid]?.presentationPath
            )
        }
        let matches = await Task.detached(priority: .userInitiated) {
            LibraryLocator.resolve(requests, roots: roots)
        }.value
        try Task.checkCancellation()

        let uniqueSources = Self.orderedUnique(matches.values.map(\.url))
        let referencedMedia = MediaLocator.findReferencedMedia(inProFiles: uniqueSources)

        let entries = detail.items.map { item -> ExportPlan.Entry in
            let uuid = item.presentationInfo?.presentationUuid
            return ExportPlan.Entry(
                item: item,
                presentation: uuid.flatMap { presentations[$0] },
                fetchError: uuid.flatMap { fetchErrors[$0] },
                match: uuid.flatMap { matches[$0] }
            )
        }

        return ExportPlan(
            playlist: detail.identifier,
            proPresenter: await versionTask,
            entries: entries,
            referencedMedia: referencedMedia,
            libraryRoots: roots,
            discoveredLibraryRoot: discoveredRoot,
            preparedAt: Date()
        )
    }

    // MARK: Export

    static let mediaFolder = "Media"

    /// Stages files + `manifest.json` in a temp folder and zips it to `destination` with `ditto`.
    func export(plan: ExportPlan, to destination: URL, includeMedia: Bool = false, progress: ProgressHandler? = nil) async throws -> ExportResult {
        let presentationEntries = plan.presentationEntries
        guard !presentationEntries.isEmpty else { throw ExportError.noPresentations }
        let missing = presentationEntries.filter { $0.match == nil }.map(\.item.name)
        guard missing.count < presentationEntries.count else { throw ExportError.nothingResolved(missing: missing) }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appending(path: "ProPack-\(UUID().uuidString)", directoryHint: .isDirectory)
        let packageName = Self.sanitizedFileName(destination.deletingPathExtension().lastPathComponent)
        let packageDir = stagingRoot.appending(path: packageName, directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: stagingRoot) }

        // 1. Copy each unique source file once (a song can appear several times with different arrangements).
        let uniqueSources = Self.orderedUnique(presentationEntries.compactMap { $0.match?.url.standardizedFileURL })
        var packagePaths: [URL: String] = [:]
        var fileInfo: [URL: Manifest.FileInfo] = [:]
        var usedPaths = Set<String>()
        do {
            try fm.createDirectory(at: packageDir.appending(path: Self.presentationsFolder), withIntermediateDirectories: true)
            for (index, source) in uniqueSources.enumerated() {
                try Task.checkCancellation()
                progress?(.init(
                    phase: .staging,
                    message: "Copying \(source.lastPathComponent)",
                    fraction: Double(index) / Double(uniqueSources.count)
                ))
                let relative = Self.uniquePath(
                    "\(Self.presentationsFolder)/\(Self.relativePath(of: source, roots: plan.libraryRoots))",
                    used: &usedPaths
                )
                let target = packageDir.appending(path: relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                packagePaths[source] = relative
                fileInfo[source] = try Self.fileInfo(packagePath: relative, source: source, copy: target)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ExportError.staging(error.localizedDescription)
        }

        // 2. Media files (if requested and present)
        var mediaFileInfo: [Manifest.FileInfo] = []
        if includeMedia && !plan.referencedMedia.isEmpty {
            do {
                try fm.createDirectory(at: packageDir.appending(path: Self.mediaFolder), withIntermediateDirectories: true)
                for (index, media) in plan.referencedMedia.enumerated() {
                    try Task.checkCancellation()
                    progress?(.init(
                        phase: .staging,
                        message: "Copying media: \(media.filename)",
                        fraction: Double(index) / Double(plan.referencedMedia.count)
                    ))
                    let relative = "\(Self.mediaFolder)/\(media.filename)"
                    let target = packageDir.appending(path: relative)
                    if !fm.fileExists(atPath: target.path) {
                        try fm.copyItem(at: media.url, to: target)
                    }
                    if let info = try? Self.fileInfo(packagePath: relative, source: media.url, copy: target) {
                        mediaFileInfo.append(info)
                    }
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                throw ExportError.staging("Media: \(error.localizedDescription)")
            }
        }

        // 3. manifest.json
        let manifest = Manifest(plan: plan, files: fileInfo, media: mediaFileInfo)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: packageDir.appending(path: Self.manifestFileName), options: .atomic)
        } catch {
            throw ExportError.staging("manifest.json: \(error.localizedDescription)")
        }

        // 4. Compress. --keepParent puts everything under a single top-level folder in the archive.
        try Task.checkCancellation()
        progress?(.init(phase: .compressing, message: "Creating \(destination.lastPathComponent)…", fraction: nil))
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        let output = try await ProcessRunner.run(
            "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", packageDir.path, destination.path]
        )
        guard output.status == 0 else {
            throw ExportError.ditto(status: output.status, message: output.stderrString)
        }

        progress?(.init(phase: .done, message: "Exported \(uniqueSources.count) presentation(s)\(mediaFileInfo.isEmpty ? "" : " and \(mediaFileInfo.count) media file(s)")", fraction: 1))
        return ExportResult(
            archiveURL: destination,
            includedFiles: uniqueSources.count,
            includedMediaFiles: mediaFileInfo.count,
            missingPresentations: missing
        )
    }

    // MARK: Helpers

    static func sanitizedFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Playlist" : cleaned
    }

    static func suggestedArchiveName(for playlistName: String, date: Date = Date(), fileExtension: String = "propack") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(sanitizedFileName(playlistName)) \(formatter.string(from: date)).\(fileExtension)"
    }

    /// Path relative to its library root (e.g. `Default/Amazing Grace.pro`), or just the file name.
    private static func relativePath(of file: URL, roots: [URL]) -> String {
        let filePath = file.resolvingSymlinksInPath().path
        for root in roots {
            let rootPath = root.resolvingSymlinksInPath().path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if filePath.hasPrefix(prefix) { return String(filePath.dropFirst(prefix.count)) }
        }
        return file.lastPathComponent
    }

    private static func uniquePath(_ path: String, used: inout Set<String>) -> String {
        guard used.contains(path.lowercased()) else {
            used.insert(path.lowercased())
            return path
        }
        let ns = path as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if used.insert(candidate.lowercased()).inserted { return candidate }
            n += 1
        }
    }

    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func fileInfo(packagePath: String, source: URL, copy: URL) throws -> Manifest.FileInfo {
        let data = try Data(contentsOf: copy, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let modified = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return .init(packagePath: packagePath, sourcePath: source.path, sizeBytes: data.count, sha256: digest, modifiedAt: modified)
    }
}

// MARK: - Manifest

/// Serialized as `manifest.json` (snake_case keys).
struct Manifest: Codable, Sendable {
    struct Generator: Codable, Sendable {
        let name: String
        let version: String
    }

    struct Source: Codable, Sendable {
        let hostDescription: String?
        let apiVersion: String?
        let platform: String?
        let osVersion: String?
    }

    struct Playlist: Codable, Sendable {
        let uuid: String
        let name: String
    }

    struct Arrangement: Codable, Sendable {
        let uuid: String?
        let name: String?
    }

    struct FileInfo: Codable, Sendable {
        let packagePath: String
        let sourcePath: String
        let sizeBytes: Int
        let sha256: String
        let modifiedAt: Date?
    }

    struct Group: Codable, Sendable {
        let name: String?
        let color: PPColor?
        let slideCount: Int
        let slideLabels: [String]
    }

    struct Item: Codable, Sendable {
        enum Status: String, Codable, Sendable {
            case included, missing, skipped
        }

        let index: Int
        let playlistItemUuid: String
        let name: String
        let type: String
        let isHidden: Bool
        let status: Status
        let presentationUuid: String?
        let arrangement: Arrangement?
        let matchMethod: MatchMethod?
        let apiPresentationPath: String?
        let file: FileInfo?
        let groups: [Group]?
        let error: String?
    }

    struct Summary: Codable, Sendable {
        let totalItems: Int
        let presentations: Int
        let included: Int
        let missing: Int
        let uniqueFiles: Int
    }

    var format: String = "propack"
    var formatVersion: Int = ExportService.manifestFormatVersion
    let exportedAt: Date
    let generator: Generator
    let source: Source?
    let playlist: Playlist
    let libraryRoots: [String]
    let summary: Summary
    let items: [Item]
    let media: [FileInfo]?

    init(plan: ExportPlan, files: [URL: FileInfo], media: [FileInfo] = [], date: Date = Date()) {
        let info = Bundle.main.infoDictionary
        exportedAt = date
        self.media = media.isEmpty ? nil : media
        generator = Generator(
            name: info?["CFBundleName"] as? String ?? "ProPack",
            version: info?["CFBundleShortVersionString"] as? String ?? "dev"
        )
        source = plan.proPresenter.map {
            Source(hostDescription: $0.hostDescription, apiVersion: $0.apiVersion, platform: $0.platform, osVersion: $0.osVersion)
        }
        playlist = Playlist(uuid: plan.playlist.uuid, name: plan.playlist.name)
        libraryRoots = plan.libraryRoots.map(\.path)

        items = plan.entries.enumerated().map { offset, entry in
            let info = entry.item.presentationInfo
            let file = entry.match.flatMap { files[$0.url.standardizedFileURL] }
            let status: Item.Status = !entry.isPresentation ? .skipped : (file != nil ? .included : .missing)
            let arrangement = info.flatMap { info -> Arrangement? in
                guard info.arrangementUuidIfSet != nil || info.arrangementNameIfSet != nil else { return nil }
                return Arrangement(uuid: info.arrangementUuidIfSet, name: info.arrangementNameIfSet)
            }
            let groups = entry.presentation?.groups?.map { group in
                Group(
                    name: group.name,
                    color: group.color,
                    slideCount: group.slides?.count ?? 0,
                    slideLabels: (group.slides ?? []).compactMap { $0.label.flatMap { $0.isEmpty ? nil : $0 } }
                )
            }
            return Item(
                index: entry.item.identifier.index ?? offset,
                playlistItemUuid: entry.item.id,
                name: entry.item.name,
                type: entry.item.kind,
                isHidden: entry.item.isHidden ?? false,
                status: status,
                presentationUuid: info?.presentationUuid,
                arrangement: arrangement,
                matchMethod: file != nil ? entry.match?.method : nil,
                apiPresentationPath: entry.presentation?.presentationPath,
                file: file,
                groups: groups,
                error: status == .missing ? (entry.fetchError ?? "No matching .pro file found in library roots") : nil
            )
        }

        let presentationItems = items.filter { $0.status != .skipped }
        summary = Summary(
            totalItems: items.count,
            presentations: presentationItems.count,
            included: presentationItems.filter { $0.status == .included }.count,
            missing: presentationItems.filter { $0.status == .missing }.count,
            uniqueFiles: files.count
        )
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
