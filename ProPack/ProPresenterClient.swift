import Foundation

// MARK: - API Models
//
// The ProPresenter REST API uses snake_case keys. All decoders in this file use
// `.convertFromSnakeCase`, so `presentation_path` maps to `presentationPath`, etc.
// Most fields are optional because the payloads vary slightly across
// ProPresenter releases; we prefer degrading gracefully over failing an export.

/// The `{ "uuid", "name", "index" }` triple ProPresenter uses to identify almost everything.
struct PPIdentifier: Codable, Hashable, Sendable {
    let uuid: String
    let name: String
    let index: Int?
}

/// `GET /version`
struct PPVersion: Codable, Hashable, Sendable {
    let name: String?
    let platform: String?
    let osVersion: String?
    let hostDescription: String?
    let apiVersion: String?

    /// Any JSON object decodes into this all-optional struct, so use this to make sure
    /// a probed port is really ProPresenter and not some other local HTTP service.
    var looksLikeProPresenter: Bool {
        apiVersion != nil || (hostDescription?.localizedCaseInsensitiveContains("ProPresenter") ?? false)
    }

    var displayString: String {
        var parts = [hostDescription ?? "ProPresenter"]
        if let apiVersion { parts.append("API \(apiVersion)") }
        return parts.joined(separator: " · ")
    }
}

/// An entry in `GET /v1/playlists`. Either a playlist or a folder ("group") of playlists.
struct PPPlaylistNode: Decodable, Hashable, Identifiable, Sendable {
    let identifier: PPIdentifier
    let fieldType: String?
    let children: [PPPlaylistNode]?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case fieldType
        case children
    }

    var id: String { identifier.uuid }
    var name: String { identifier.name }
    var isGroup: Bool { fieldType == "group" }

    /// For `OutlineGroup`: `nil` marks a leaf (an actual playlist).
    var outlineChildren: [PPPlaylistNode]? { isGroup ? (children ?? []) : nil }

    /// Depth-first search through the playlist tree.
    static func find(_ id: String, in nodes: [PPPlaylistNode]) -> PPPlaylistNode? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = find(id, in: node.children ?? []) { return hit }
        }
        return nil
    }

    /// All leaf playlists in tree order.
    static func leaves(of nodes: [PPPlaylistNode]) -> [PPPlaylistNode] {
        nodes.flatMap { $0.isGroup ? leaves(of: $0.children ?? []) : [$0] }
    }
}

/// `GET /v1/playlist/{id}`
struct PPPlaylistDetail: Decodable, Sendable {
    let identifier: PPIdentifier
    let items: [PPPlaylistItem]

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(PPIdentifier.self, forKey: .identifier)
        items = try c.decodeIfPresent([PPPlaylistItem].self, forKey: .items) ?? []
    }

    var presentationItems: [PPPlaylistItem] { items.filter(\.isPresentation) }
}

/// A single row in a playlist: presentation, header, media, placeholder, cue, …
struct PPPlaylistItem: Decodable, Hashable, Identifiable, Sendable {
    let identifier: PPIdentifier
    let type: String?
    let isHidden: Bool?
    let isPco: Bool?
    let presentationInfo: PPPresentationInfo?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case type, isHidden, isPco, presentationInfo
    }

    init(identifier: PPIdentifier, type: String? = nil, isHidden: Bool? = nil, isPco: Bool? = nil, presentationInfo: PPPresentationInfo? = nil) {
        self.identifier = identifier
        self.type = type
        self.isHidden = isHidden
        self.isPco = isPco
        self.presentationInfo = presentationInfo
    }

    var id: String { identifier.uuid }
    var name: String { identifier.name }
    var kind: String { type ?? "unknown" }
    var isPresentation: Bool { kind == "presentation" && presentationInfo != nil }
}

/// Presentation reference + the arrangement chosen for this playlist entry.
struct PPPresentationInfo: Codable, Hashable, Sendable {
    let presentationUuid: String
    let arrangementName: String?
    let arrangementUuid: String?

    /// ProPresenter sends empty strings when no arrangement is selected.
    var arrangementNameIfSet: String? { arrangementName.flatMap { $0.isEmpty ? nil : $0 } }
    var arrangementUuidIfSet: String? { arrangementUuid.flatMap { $0.isEmpty ? nil : $0 } }
}

/// `GET /v1/presentation/{uuid}` → `{ "presentation": { … } }`
struct PPPresentation: Decodable, Sendable {
    let identifier: PPIdentifier
    let groups: [PPGroup]?
    let hasTimeline: Bool?
    /// Absolute path to the `.pro` file on disk (used for library discovery + file matching).
    let presentationPath: String?
    let destination: String?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case groups, hasTimeline, presentationPath, destination
    }

    init(identifier: PPIdentifier, groups: [PPGroup]? = nil, hasTimeline: Bool? = nil, presentationPath: String? = nil, destination: String? = nil) {
        self.identifier = identifier
        self.groups = groups
        self.hasTimeline = hasTimeline
        self.presentationPath = presentationPath
        self.destination = destination
    }
}

struct PPGroup: Codable, Hashable, Sendable {
    let name: String?
    let color: PPColor?
    let slides: [PPSlide]?

    init(name: String? = nil, color: PPColor? = nil, slides: [PPSlide]? = nil) {
        self.name = name
        self.color = color
        self.slides = slides
    }
}

struct PPColor: Codable, Hashable, Sendable {
    let red: Double?
    let green: Double?
    let blue: Double?
    let alpha: Double?
}

struct PPSlide: Codable, Hashable, Sendable {
    let enabled: Bool?
    let notes: String?
    let text: String?
    let label: String?

    init(enabled: Bool? = true, notes: String? = nil, text: String? = nil, label: String? = nil) {
        self.enabled = enabled
        self.notes = notes
        self.text = text
        self.label = label
    }
}

/// An entry in `GET /v1/libraries`.
struct PPLibrary: Codable, Hashable, Identifiable, Sendable {
    let uuid: String
    let name: String
    let index: Int?

    var id: String { uuid }
}

/// Response from `GET /v1/library/{id}`.
struct PPLibraryResponse: Codable, Sendable {
    let updateType: String?
    let items: [PPLibraryItem]
}

/// An entry in `GET /v1/library/{id}` items.
struct PPLibraryItem: Codable, Hashable, Identifiable, Sendable {
    let uuid: String
    let name: String
    let index: Int?

    var id: String { uuid }
}

/// Payload sent in `PUT /v1/playlist/{id}` to set playlist items.
struct PPPlaylistItemPayload: Encodable, Sendable {
    struct IdentifierPayload: Encodable, Sendable {
        let uuid: String
        let name: String
        let index: Int
    }
    struct PresentationInfoPayload: Encodable, Sendable {
        let presentationUuid: String
        let arrangementName: String
        let arrangementUuid: String
    }

    let id: IdentifierPayload
    let type: String
    let isHidden: Bool
    let isPco: Bool
    let presentationInfo: PresentationInfoPayload?
    let destination: String
    let targetUuid: String
}

/// Summary of a ProPresenter Audience Look (`GET /v1/look/current` or `GET /v1/looks`),
/// including any alternate presentation themes referenced across its screens/layers.
struct PPLookSummary: Codable, Hashable, Identifiable, Sendable {
    let identifier: PPIdentifier
    let isLive: Bool
    let referencedThemes: [PPIdentifier]
    let rawJSONBase64: String?

    var id: String { identifier.uuid }
    var name: String { identifier.name }

    init(
        identifier: PPIdentifier,
        isLive: Bool = false,
        referencedThemes: [PPIdentifier] = [],
        rawJSONBase64: String? = nil
    ) {
        self.identifier = identifier
        self.isLive = isLive
        self.referencedThemes = referencedThemes
        self.rawJSONBase64 = rawJSONBase64
    }

    /// Parses a single Audience Look JSON payload from `/v1/look/current` or `/v1/look/{id}`.
    static func parse(from data: Data, isLive: Bool = false) -> PPLookSummary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = root as? [String: Any] {
            let lookDict = (dict["look"] as? [String: Any]) ?? dict
            return parseDictionary(lookDict, isLive: isLive)
        }
        return nil
    }

    /// Parses a list of Audience Looks from `/v1/looks`.
    static func parseList(from data: Data) -> [PPLookSummary] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let array: [[String: Any]]
        if let list = root as? [[String: Any]] {
            array = list
        } else if let dict = root as? [String: Any], let list = dict["looks"] as? [[String: Any]] {
            array = list
        } else {
            return []
        }
        return array.compactMap { parseDictionary($0, isLive: false) }
    }

    private static func parseDictionary(_ dict: [String: Any], isLive: Bool) -> PPLookSummary? {
        let idDict = (dict["id"] as? [String: Any]) ?? dict
        let uuid = (idDict["uuid"] as? String) ?? ""
        let name = (idDict["name"] as? String) ?? (dict["name"] as? String) ?? (isLive ? "Live Look" : "")
        let index = idDict["index"] as? Int
        guard !uuid.isEmpty || !name.isEmpty else { return nil }

        var themes: [PPIdentifier] = []
        var seen = Set<String>()
        extractThemes(from: dict, into: &themes, seen: &seen)

        let rawBase64 = (try? JSONSerialization.data(withJSONObject: dict)).map { $0.base64EncodedString() }
        return PPLookSummary(
            identifier: PPIdentifier(uuid: uuid.isEmpty ? name : uuid, name: name, index: index),
            isLive: isLive,
            referencedThemes: themes,
            rawJSONBase64: rawBase64
        )
    }

    private static func extractThemes(from value: Any, into results: inout [PPIdentifier], seen: inout Set<String>) {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                let lowerKey = key.lowercased()
                if lowerKey == "presentation_theme" || lowerKey == "presentationtheme" || lowerKey == "theme" || lowerKey == "template" {
                    if let themeDict = child as? [String: Any] {
                        let idContainer = (themeDict["id"] as? [String: Any]) ?? themeDict
                        let uuid = (idContainer["uuid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let name = (idContainer["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let index = idContainer["index"] as? Int
                        if !uuid.isEmpty || !name.isEmpty {
                            let dedupKey = "\(uuid.lowercased())|\(name.lowercased())"
                            if seen.insert(dedupKey).inserted {
                                results.append(PPIdentifier(uuid: uuid, name: name, index: index))
                            }
                        }
                    } else if let themeName = child as? String {
                        let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let dedupKey = "|\(trimmed.lowercased())"
                            if seen.insert(dedupKey).inserted {
                                results.append(PPIdentifier(uuid: "", name: trimmed, index: nil))
                            }
                        }
                    }
                }
                extractThemes(from: child, into: &results, seen: &seen)
            }
        } else if let array = value as? [Any] {
            for element in array {
                extractThemes(from: element, into: &results, seen: &seen)
            }
        }
    }
}

// MARK: - Errors

enum ProPresenterClientError: LocalizedError {
    case invalidURL(String)
    case unreachable(port: Int, detail: String)
    case httpStatus(Int, path: String)
    case decoding(path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "Invalid request URL: \(path)"
        case .unreachable(let port, let detail):
            "Could not reach ProPresenter on port \(port). \(detail)"
        case .httpStatus(let code, let path):
            "ProPresenter returned HTTP \(code) for \(path)."
        case .decoding(let path, let detail):
            "Unexpected response from \(path): \(detail)"
        }
    }
}

// MARK: - Client

/// Thin, stateless wrapper around the ProPresenter v1 REST API on localhost.
struct ProPresenterClient: Sendable {
    static let defaultHost = "127.0.0.1"

    /// One shared ephemeral session; per-request timeouts are set on each `URLRequest`
    /// so short-timeout port probes don't need their own sessions.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    let host: String
    let port: Int
    let timeout: TimeInterval

    init(host: String = defaultHost, port: Int, timeout: TimeInterval = 8) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    // MARK: Endpoints

    func version() async throws -> PPVersion {
        try decode(PPVersion.self, from: try await fetch("/version"), path: "/version")
    }

    func playlists() async throws -> [PPPlaylistNode] {
        let path = "/v1/playlists"
        return try decode([PPPlaylistNode].self, from: try await fetch(path), path: path)
    }

    func playlist(id: String) async throws -> PPPlaylistDetail {
        let path = "/v1/playlist/\(Self.escape(id))"
        let data = try await fetch(path)
        // Some builds wrap the playlist in a single-element array.
        if let wrapped = try? makeDecoder().decode([PPPlaylistDetail].self, from: data), let first = wrapped.first {
            return first
        }
        return try decode(PPPlaylistDetail.self, from: data, path: path)
    }

    func presentation(uuid: String) async throws -> PPPresentation {
        struct Envelope: Decodable { let presentation: PPPresentation }
        let path = "/v1/presentation/\(Self.escape(uuid))"
        let data = try await fetch(path)
        if let envelope = try? makeDecoder().decode(Envelope.self, from: data) {
            return envelope.presentation
        }
        return try decode(PPPresentation.self, from: data, path: path)
    }

    func libraries() async throws -> [PPLibrary] {
        let path = "/v1/libraries"
        return try decode([PPLibrary].self, from: try await fetch(path), path: path)
    }

    func libraryItems(id: String) async throws -> [PPLibraryItem] {
        let path = "/v1/library/\(Self.escape(id))"
        let response = try decode(PPLibraryResponse.self, from: try await fetch(path), path: path)
        return response.items
    }

    func createPlaylist(name: String, type: String = "playlist") async throws -> PPPlaylistNode {
        struct CreateBody: Encodable {
            let name: String
            let type: String
        }
        let body = try JSONEncoder().encode(CreateBody(name: name, type: type))
        let data = try await send(path: "/v1/playlists", method: "POST", body: body)
        return try decode(PPPlaylistNode.self, from: data, path: "/v1/playlists")
    }

    func updatePlaylistItems(id: String, items: [PPPlaylistItemPayload]) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try encoder.encode(items)
        _ = try await send(path: "/v1/playlist/\(Self.escape(id))", method: "PUT", body: body)
    }

    func currentLook() async throws -> PPLookSummary {
        let path = "/v1/look/current"
        let data = try await fetch(path)
        guard let look = PPLookSummary.parse(from: data, isLive: true) else {
            throw ProPresenterClientError.decoding(path: path, detail: "Invalid Look JSON payload")
        }
        return look
    }

    func looks() async throws -> [PPLookSummary] {
        let path = "/v1/looks"
        let data = try await fetch(path)
        return PPLookSummary.parseList(from: data)
    }

    func syncAudienceLook(_ look: PPLookSummary) async {
        guard let rawBase64 = look.rawJSONBase64,
              let rawData = Data(base64Encoded: rawBase64) else { return }

        if look.isLive {
            _ = try? await send(path: "/v1/look/current", method: "PUT", body: rawData)
        } else {
            let existing = (try? await looks()) ?? []
            if let match = existing.first(where: {
                $0.id.caseInsensitiveCompare(look.id) == .orderedSame ||
                $0.name.localizedCaseInsensitiveCompare(look.name) == .orderedSame
            }) {
                _ = try? await send(path: "/v1/look/\(Self.escape(match.id))", method: "PUT", body: rawData)
            } else {
                _ = try? await send(path: "/v1/looks", method: "POST", body: rawData)
            }
        }
    }

    // MARK: Plumbing

    private var baseURL: URL? { URL(string: "http://\(host):\(port)") }

    private func fetch(_ path: String) async throws -> Data {
        try await send(path: path, method: "GET", body: nil)
    }

    private func send(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ProPresenterClientError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw ProPresenterClientError.unreachable(port: port, detail: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProPresenterClientError.unreachable(port: port, detail: "Non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProPresenterClientError.httpStatus(http.statusCode, path: path)
        }
        return data
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch {
            throw ProPresenterClientError.decoding(path: path, detail: String(describing: error))
        }
    }

    private static func escape(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
