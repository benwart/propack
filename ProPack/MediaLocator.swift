import Foundation

// MARK: - Media Asset

public struct MediaAsset: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case video = "Video"
        case image = "Image"
        case audio = "Audio"
        case other = "Other"

        public static func from(extension ext: String) -> Kind {
            switch ext.lowercased() {
            case "mp4", "mov", "m4v", "webm", "avi", "mkv": return .video
            case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp": return .image
            case "mp3", "wav", "m4a", "aac", "aif", "aiff": return .audio
            default: return .other
            }
        }
    }

    public var id: String { url.path }
    public let url: URL
    public let filename: String
    public let sizeBytes: Int64
    public let kind: Kind

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Media Locator

public enum MediaLocator {
    public static var defaultMediaRoots: [URL] {
        var roots: [URL] = []
        for workspace in LibraryLocator.detectedWorkspaceDirectories {
            let mediaDir = workspace.appending(path: "Media", directoryHint: .isDirectory)
            roots.append(mediaDir)
            roots.append(mediaDir.appending(path: "Assets", directoryHint: .isDirectory))
            roots.append(mediaDir.appending(path: "Imported", directoryHint: .isDirectory))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots.append(contentsOf: [
            home.appending(path: "Documents/ProPresenter/Media", directoryHint: .isDirectory),
            home.appending(path: "Movies", directoryHint: .isDirectory),
            home.appending(path: "Pictures", directoryHint: .isDirectory),
            home.appending(path: "Music", directoryHint: .isDirectory)
        ])
        return roots
    }

    /// Infers the target `Media` directory corresponding to a target library folder on import.
    public static func targetMediaDirectory(forTargetLibraryURL targetLibraryURL: URL) -> URL {
        let workspace = LibraryLocator.workspaceDirectory(forTargetLibraryURL: targetLibraryURL)
        return workspace.appending(path: "Media", directoryHint: .isDirectory)
    }

    /// Extracts referenced media files from an array of .pro files.
    public static func findReferencedMedia(inProFiles proURLs: [URL]) -> [MediaAsset] {
        var foundAssets: [URL: MediaAsset] = [:]

        for proURL in proURLs {
            guard let data = try? Data(contentsOf: proURL, options: .mappedIfSafe) else { continue }
            let referencedPaths = extractPotentialMediaPaths(from: data)

            for pathCandidate in referencedPaths {
                if let resolvedURL = resolveMediaURL(pathCandidate) {
                    if foundAssets[resolvedURL] == nil {
                        let size = (try? resolvedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                        let kind = MediaAsset.Kind.from(extension: resolvedURL.pathExtension)
                        foundAssets[resolvedURL] = MediaAsset(
                            url: resolvedURL,
                            filename: resolvedURL.lastPathComponent,
                            sizeBytes: size,
                            kind: kind
                        )
                    }
                }
            }
        }

        return Array(foundAssets.values).sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    /// Scans raw binary protobuf data for paths ending in media extensions.
    public static func extractPotentialMediaPaths(from data: Data) -> [String] {
        guard let asciiString = String(data: data, encoding: .ascii) else { return [] }
        var paths: [String] = []

        let pattern = #"(?:/[^\x00-\x1F\x7F-\xFF]+|\b[a-zA-Z0-9_\- ]+)\.(?:mp4|mov|m4v|webm|jpg|jpeg|png|heic|gif|mp3|wav|m4a|aac)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

        let nsString = asciiString as NSString
        let matches = regex.matches(in: asciiString, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let candidate = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                paths.append(candidate)
            }
        }

        return paths
    }

    public static func resolveMediaURL(_ candidate: String) -> URL? {
        let fm = FileManager.default
        let expanded = (candidate as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") && fm.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }

        let filename = URL(fileURLWithPath: candidate).lastPathComponent
        for root in defaultMediaRoots {
            let candidateURL = root.appending(path: filename)
            if fm.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }
}
