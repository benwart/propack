import Foundation
import SwiftUI

// MARK: - Sort Options

enum PlaylistSortField: String, CaseIterable, Identifiable, Codable, Sendable {
    case date
    case name

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .date: return "Date"
        case .name: return "Name"
        }
    }
}

enum PlaylistSortOrder: String, CaseIterable, Identifiable, Codable, Sendable {
    case descending // Newest first (for date) or Z -> A (for name)
    case ascending  // Oldest first (for date) or A -> Z (for name)

    var id: String { rawValue }

    func label(for field: PlaylistSortField) -> String {
        switch (field, self) {
        case (.date, .descending): return "Newest First"
        case (.date, .ascending): return "Oldest First"
        case (.name, .ascending): return "A → Z"
        case (.name, .descending): return "Z → A"
        }
    }
}

enum PlaylistSortOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case dateDescending = "date_desc"
    case dateAscending = "date_asc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"

    var id: String { rawValue }

    var field: PlaylistSortField {
        switch self {
        case .dateDescending, .dateAscending: return .date
        case .nameAscending, .nameDescending: return .name
        }
    }

    var order: PlaylistSortOrder {
        switch self {
        case .dateDescending, .nameDescending: return .descending
        case .dateAscending, .nameAscending: return .ascending
        }
    }

    var label: String {
        switch self {
        case .dateDescending: return "Date (Newest First)"
        case .dateAscending: return "Date (Oldest First)"
        case .nameAscending: return "Name (A → Z)"
        case .nameDescending: return "Name (Z → A)"
        }
    }

    var shortLabel: String {
        switch self {
        case .dateDescending: return "Newest"
        case .dateAscending: return "Oldest"
        case .nameAscending: return "A → Z"
        case .nameDescending: return "Z → A"
        }
    }

    var iconName: String {
        switch self {
        case .dateDescending: return "calendar.badge.clock"
        case .dateAscending: return "calendar"
        case .nameAscending: return "textformat.abc"
        case .nameDescending: return "textformat.abc"
        }
    }

    init(field: PlaylistSortField, order: PlaylistSortOrder) {
        switch (field, order) {
        case (.date, .descending): self = .dateDescending
        case (.date, .ascending): self = .dateAscending
        case (.name, .ascending): self = .nameAscending
        case (.name, .descending): self = .nameDescending
        }
    }
}

// MARK: - Date Parser

enum PlaylistDateParser {
    // Common date patterns in playlist names:
    // 1. ISO (2026-10-18, 2026.10.18, 2026_10_18)
    private static let isoRegex = try! NSRegularExpression(pattern: #"(?<!\d)(20\d{2})[-_.](0?[1-9]|1[0-2])[-_.](0?[1-9]|[12]\d|3[01])(?!\d)"#)
    // 2. Compact ISO (20261018)
    private static let compactIsoRegex = try! NSRegularExpression(pattern: #"(?<!\d)(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)"#)
    // 3. US full year (10-18-2026, 10/18/2026, 10.18.2026)
    private static let usRegex = try! NSRegularExpression(pattern: #"(?<!\d)(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])[-/.](20\d{2})(?!\d)"#)
    // 4. US short year (10-18-26, 10/18/26, 10.18.26)
    private static let usShortYearRegex = try! NSRegularExpression(pattern: #"(?<!\d)(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])[-/.]([2-3]\d)(?!\d)"#)
    // 5. Month-Day without year (10.18, 10/18, 10-18)
    private static let monthDayRegex = try! NSRegularExpression(pattern: #"(?<!\d)(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])(?!\d)"#)

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fullRange = NSRange(location: 0, length: trimmed.utf16.count)

        // 1. ISO (yyyy-MM-dd, yyyy.MM.dd, yyyy_MM_dd)
        if let match = isoRegex.firstMatch(in: trimmed, options: [], range: fullRange),
           let r = Range(match.range, in: trimmed) {
            let s = String(trimmed[r]).replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "_", with: "-")
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: s) { return Calendar.current.startOfDay(for: d) }
        }

        // 2. Compact ISO (yyyyMMdd)
        if let match = compactIsoRegex.firstMatch(in: trimmed, options: [], range: fullRange),
           let r = Range(match.range, in: trimmed) {
            let s = String(trimmed[r])
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyyMMdd"
            if let d = fmt.date(from: s) { return Calendar.current.startOfDay(for: d) }
        }

        // 3. US format (MM-dd-yyyy, MM/dd/yyyy, MM.dd.yyyy)
        if let match = usRegex.firstMatch(in: trimmed, options: [], range: fullRange),
           let r = Range(match.range, in: trimmed) {
            let s = String(trimmed[r]).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "MM-dd-yyyy"
            if let d = fmt.date(from: s) { return Calendar.current.startOfDay(for: d) }
        }

        // 4. US short year (MM-dd-yy, MM/dd/yy, MM.dd.yy)
        if let match = usShortYearRegex.firstMatch(in: trimmed, options: [], range: fullRange),
           let r = Range(match.range, in: trimmed) {
            let s = String(trimmed[r]).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "MM-dd-yy"
            if let d = fmt.date(from: s) { return Calendar.current.startOfDay(for: d) }
        }

        // 5. Month-Day without year (MM-dd, MM/dd, MM.dd)
        if let match = monthDayRegex.firstMatch(in: trimmed, options: [], range: fullRange),
           let r = Range(match.range, in: trimmed) {
            let s = String(trimmed[r]).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
            let year = Calendar.current.component(.year, from: Date())
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: "\(year)-\(s)") { return Calendar.current.startOfDay(for: d) }
        }

        // 6. Natural language dates via NSDataDetector (e.g. "October 18, 2026", "Oct 18")
        if let detector = detector,
           let match = detector.firstMatch(in: trimmed, options: [], range: fullRange),
           let d = match.date {
            return Calendar.current.startOfDay(for: d)
        }

        return nil
    }

    private static let displayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()

    static func formatDisplay(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}

// MARK: - Fuzzy Matcher (fzf-style)

struct FuzzyMatch: Comparable, Sendable, Hashable {
    let score: Int
    let matchedIndices: [Int]

    init(score: Int, matchedIndices: [Int] = []) {
        self.score = score
        self.matchedIndices = matchedIndices
    }

    static func < (lhs: FuzzyMatch, rhs: FuzzyMatch) -> Bool {
        lhs.score < rhs.score
    }
}

enum FuzzyMatcher {
    /// Fuzzy matches pattern in target.
    /// Supports multi-term space-separated queries (fzf AND logic).
    static func score(pattern: String, in target: String) -> FuzzyMatch? {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return FuzzyMatch(score: 0, matchedIndices: [])
        }

        let tokens = trimmedPattern.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return FuzzyMatch(score: 0, matchedIndices: [])
        }

        let targetChars = Array(target)
        let targetLower = Array(target.lowercased())

        if tokens.count == 1 {
            return scoreToken(patternChars: Array(tokens[0].lowercased()), targetLower: targetLower, targetOrig: targetChars)
        }

        // Multi-term: All tokens must match target (fzf AND behavior)
        var totalScore = 0
        var allIndices: [Int] = []
        for token in tokens {
            guard let match = scoreToken(patternChars: Array(token.lowercased()), targetLower: targetLower, targetOrig: targetChars) else {
                return nil
            }
            totalScore += match.score
            allIndices.append(contentsOf: match.matchedIndices)
        }

        return FuzzyMatch(score: totalScore, matchedIndices: Array(Set(allIndices)).sorted())
    }

    private static func scoreToken(patternChars: [Character], targetLower: [Character], targetOrig: [Character]) -> FuzzyMatch? {
        guard patternChars.count <= targetLower.count else { return nil }

        var patternIdx = 0
        var matchedIndices: [Int] = []
        var score = 0
        var consecutiveCount = 0
        var prevMatchedIdx = -1

        for (targetIdx, char) in targetLower.enumerated() {
            if patternIdx < patternChars.count && char == patternChars[patternIdx] {
                matchedIndices.append(targetIdx)
                var charScore = 2

                // Consecutive match bonus
                if prevMatchedIdx == targetIdx - 1 {
                    consecutiveCount += 1
                    charScore += 3 * consecutiveCount
                } else {
                    consecutiveCount = 0
                }

                // Word boundary bonus
                if targetIdx == 0 {
                    charScore += 10 // Start of target
                } else {
                    let prevChar = targetOrig[targetIdx - 1]
                    if prevChar.isWhitespace || prevChar == "-" || prevChar == "_" || prevChar == "." || prevChar == "/" || prevChar == "(" || prevChar == "[" {
                        charScore += 8 // Right after separator
                    } else if prevChar.isLowercase && targetOrig[targetIdx].isUppercase {
                        charScore += 6 // CamelCase transition
                    }
                }

                score += charScore
                prevMatchedIdx = targetIdx
                patternIdx += 1
            }
        }

        // Ensure all characters in pattern were matched in order
        guard patternIdx == patternChars.count else { return nil }

        let pStr = String(patternChars)
        let tStr = String(targetLower)

        // Exact match bonus
        if tStr == pStr {
            score += 50
        } else if tStr.hasPrefix(pStr) {
            score += 25
        } else if tStr.contains(pStr) {
            score += 15
        }

        // Distance / compactness bonus (penalize wide gaps)
        if let first = matchedIndices.first, let last = matchedIndices.last {
            let span = last - first + 1
            if span == patternChars.count {
                score += 10 // perfectly contiguous
            } else {
                score -= (span - patternChars.count)
            }
        }

        return FuzzyMatch(score: score, matchedIndices: matchedIndices)
    }

    /// Generates an AttributedString with matched character positions highlighted.
    static func highlightedString(for text: String, matchedIndices: [Int], highlightColor: Color = .accentColor) -> AttributedString {
        var attributed = AttributedString(text)
        guard !matchedIndices.isEmpty else { return attributed }

        let indicesSet = Set(matchedIndices)
        var currentIndex = attributed.startIndex

        for (offset, _) in text.enumerated() {
            let nextIndex = attributed.index(afterCharacter: currentIndex)
            if indicesSet.contains(offset) {
                attributed[currentIndex..<nextIndex].inlinePresentationIntent = .stronglyEmphasized
                attributed[currentIndex..<nextIndex].foregroundColor = highlightColor
            }
            currentIndex = nextIndex
        }

        return attributed
    }
}

// MARK: - Search & List Row Model

struct PlaylistRowItem: Identifiable, Hashable, Sendable {
    let node: PPPlaylistNode
    let folderPath: String?
    let effectiveDate: Date?
    let match: FuzzyMatch?

    var id: String { node.id }
    var name: String { node.name }

    init(node: PPPlaylistNode, folderPath: String? = nil, effectiveDate: Date? = nil, match: FuzzyMatch? = nil) {
        self.node = node
        self.folderPath = folderPath
        self.effectiveDate = effectiveDate ?? node.effectiveDate
        self.match = match
    }
}

// MARK: - PPPlaylistNode Extensions

extension PPPlaylistNode {
    /// Inferred or explicit date associated with this playlist.
    var effectiveDate: Date? {
        if let explicit = date { return explicit }
        if isGroup {
            let childDates = (children ?? []).compactMap { $0.effectiveDate }
            return childDates.max() ?? PlaylistDateParser.parse(from: name)
        }
        return PlaylistDateParser.parse(from: name)
    }

    /// Formatted date string for UI display (e.g. "Oct 18, 2026").
    var formattedDateString: String? {
        effectiveDate.map { PlaylistDateParser.formatDisplay($0) }
    }

    /// Recursively sorts this node (if group) and all its descendant groups.
    func sorted(by field: PlaylistSortField, order: PlaylistSortOrder) -> PPPlaylistNode {
        guard isGroup, let children = children else { return self }
        let sortedChildren = children
            .map { $0.sorted(by: field, order: order) }
            .sorted { a, b in
                PPPlaylistNode.compare(a, b, field: field, order: order)
            }
        return PPPlaylistNode(
            identifier: identifier,
            fieldType: fieldType,
            children: sortedChildren,
            date: date
        )
    }

    /// Comparator for two playlist nodes.
    static func compare(_ a: PPPlaylistNode, _ b: PPPlaylistNode, field: PlaylistSortField, order: PlaylistSortOrder) -> Bool {
        switch field {
        case .date:
            switch (a.effectiveDate, b.effectiveDate) {
            case let (d1?, d2?):
                if d1 != d2 {
                    return order == .descending ? d1 > d2 : d1 < d2
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case (_?, nil):
                // Items with dates appear first when descending
                return order == .descending
            case (nil, _?):
                return order != .descending
            case (nil, nil):
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        case .name:
            let cmp = a.name.localizedStandardCompare(b.name)
            return order == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    /// Recursively flattens the tree into leaf playlists with their folder path.
    static func flatten(nodes: [PPPlaylistNode], currentPath: String? = nil) -> [PlaylistRowItem] {
        var results: [PlaylistRowItem] = []
        for node in nodes {
            if node.isGroup {
                let subPath = currentPath == nil ? node.name : "\(currentPath!) ▸ \(node.name)"
                results.append(contentsOf: flatten(nodes: node.children ?? [], currentPath: subPath))
            } else {
                results.append(PlaylistRowItem(node: node, folderPath: currentPath, effectiveDate: node.effectiveDate, match: nil))
            }
        }
        return results
    }

    /// Fuzzy search across all leaf playlists with fzf-style matching.
    static func search(
        nodes: [PPPlaylistNode],
        query: String,
        sortOption: PlaylistSortOption = .dateDescending
    ) -> [PlaylistRowItem] {
        let flattened = flatten(nodes: nodes)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return flattened.sorted { a, b in
                PPPlaylistNode.compare(a.node, b.node, field: sortOption.field, order: sortOption.order)
            }
        }

        var matches: [PlaylistRowItem] = []
        for item in flattened {
            let nameMatch = FuzzyMatcher.score(pattern: trimmed, in: item.node.name)
            let pathMatch: FuzzyMatch?
            if let path = item.folderPath {
                pathMatch = FuzzyMatcher.score(pattern: trimmed, in: "\(path) / \(item.node.name)")
            } else {
                pathMatch = nil
            }

            let bestMatch: FuzzyMatch?
            switch (nameMatch, pathMatch) {
            case let (m1?, m2?):
                bestMatch = m1.score >= m2.score ? m1 : m2
            case let (m1?, nil):
                bestMatch = m1
            case let (nil, m2?):
                bestMatch = m2
            case (nil, nil):
                bestMatch = nil
            }

            if let bestMatch {
                matches.append(PlaylistRowItem(
                    node: item.node,
                    folderPath: item.folderPath,
                    effectiveDate: item.effectiveDate,
                    match: bestMatch
                ))
            }
        }

        // Sort results: primary sort by active sort criteria (default: newest at the top)
        return matches.sorted { a, b in
            if sortOption.field == .date {
                switch (a.effectiveDate, b.effectiveDate) {
                case let (d1?, d2?) where d1 != d2:
                    return sortOption.order == .descending ? d1 > d2 : d1 < d2
                case (_?, nil):
                    return sortOption.order == .descending
                case (nil, _?):
                    return sortOption.order != .descending
                default:
                    break
                }
            } else if sortOption.field == .name {
                let cmp = a.node.name.localizedStandardCompare(b.node.name)
                if cmp != .orderedSame {
                    return sortOption.order == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
                }
            }

            // Secondary tiebreaker: highest fuzzy match score
            if let m1 = a.match, let m2 = b.match, m1.score != m2.score {
                return m1.score > m2.score
            }

            return a.node.name.localizedStandardCompare(b.node.name) == .orderedAscending
        }
    }
}

extension Array where Element == PPPlaylistNode {
    /// Sorts the entire playlist hierarchy recursively by field and order.
    func sortedTree(by field: PlaylistSortField, order: PlaylistSortOrder) -> [PPPlaylistNode] {
        self.map { $0.sorted(by: field, order: order) }
            .sorted { a, b in
                PPPlaylistNode.compare(a, b, field: field, order: order)
            }
    }

    /// Sorts the entire playlist hierarchy recursively using a sort option.
    func sortedTree(by option: PlaylistSortOption) -> [PPPlaylistNode] {
        sortedTree(by: option.field, order: option.order)
    }
}
