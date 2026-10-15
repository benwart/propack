import Foundation

@MainActor
func runPlaylistFilterTests() async {
    let suite = TestSuite.shared

    // MARK: - Date Parser Tests

    await suite.run(name: "PlaylistDateParser parses ISO date formats") {
        let cal = Calendar.current

        let date1 = PlaylistDateParser.parse(from: "2026-10-18 Sunday Morning")
        try assertTrue(date1 != nil, "Expected date parsed from 2026-10-18 Sunday Morning")
        let c1 = cal.dateComponents([.year, .month, .day], from: date1!)
        try assertTrue(c1.year == 2026 && c1.month == 10 && c1.day == 18, "Expected 2026-10-18")

        let date2 = PlaylistDateParser.parse(from: "Service 2026.12.25 Christmas")
        try assertTrue(date2 != nil, "Expected date parsed from 2026.12.25")
        let c2 = cal.dateComponents([.year, .month, .day], from: date2!)
        try assertTrue(c2.year == 2026 && c2.month == 12 && c2.day == 25, "Expected 2026-12-25")

        let date3 = PlaylistDateParser.parse(from: "2026_07_04_Summer")
        try assertTrue(date3 != nil, "Expected date parsed from 2026_07_04")
        let c3 = cal.dateComponents([.year, .month, .day], from: date3!)
        try assertTrue(c3.year == 2026 && c3.month == 7 && c3.day == 4, "Expected 2026-07-04")
    }

    await suite.run(name: "PlaylistDateParser parses compact ISO and US date formats") {
        let cal = Calendar.current

        // Compact ISO: 20261018
        let dateCompact = PlaylistDateParser.parse(from: "20261018 Service")
        try assertTrue(dateCompact != nil, "Expected date parsed from 20261018")
        let cc = cal.dateComponents([.year, .month, .day], from: dateCompact!)
        try assertTrue(cc.year == 2026 && cc.month == 10 && cc.day == 18, "Expected 2026-10-18")

        // US full year: 10/18/2026
        let dateUS = PlaylistDateParser.parse(from: "Sunday 10/18/2026")
        try assertTrue(dateUS != nil, "Expected date parsed from 10/18/2026")
        let cu = cal.dateComponents([.year, .month, .day], from: dateUS!)
        try assertTrue(cu.year == 2026 && cu.month == 10 && cu.day == 18, "Expected 2026-10-18")

        // US short year: 10-18-26
        let dateShortYear = PlaylistDateParser.parse(from: "Youth 10-18-26")
        try assertTrue(dateShortYear != nil, "Expected date parsed from 10-18-26")
        let cs = cal.dateComponents([.year, .month, .day], from: dateShortYear!)
        try assertTrue(cs.year == 2026 && cs.month == 10 && cs.day == 18, "Expected 2026-10-18")
    }

    await suite.run(name: "PlaylistDateParser parses natural text and returns nil when no date") {
        let naturalDate = PlaylistDateParser.parse(from: "October 18, 2026 Sunday Morning")
        try assertTrue(naturalDate != nil, "Expected date parsed from natural text")

        let noDate = PlaylistDateParser.parse(from: "Worship Night Announcements")
        try assertTrue(noDate == nil, "Expected nil for playlist without date")
    }

    // MARK: - Fuzzy Matcher Tests

    await suite.run(name: "FuzzyMatcher performs subsequence matching") {
        // Query 'sun' in 'Sunday Morning'
        let m1 = FuzzyMatcher.score(pattern: "sun", in: "Sunday Morning")
        try assertTrue(m1 != nil, "Expected 'sun' to match 'Sunday Morning'")
        try assertTrue(m1!.matchedIndices == [0, 1, 2], "Expected matched indices [0, 1, 2]")

        // Query 'sm' in 'Sunday Morning' (first letters of words)
        let m2 = FuzzyMatcher.score(pattern: "sm", in: "Sunday Morning")
        try assertTrue(m2 != nil, "Expected 'sm' to match 'Sunday Morning'")
        try assertTrue(m2!.matchedIndices == [0, 7], "Expected matched indices [0, 7]")

        // Query '1018' in '2026-10-18 Service'
        let m3 = FuzzyMatcher.score(pattern: "1018", in: "2026-10-18 Service")
        try assertTrue(m3 != nil, "Expected '1018' to match '2026-10-18 Service'")

        // Non-matching query
        let m4 = FuzzyMatcher.score(pattern: "xyz", in: "Sunday Morning")
        try assertTrue(m4 == nil, "Expected 'xyz' not to match 'Sunday Morning'")
    }

    await suite.run(name: "FuzzyMatcher supports multi-term queries (fzf AND behavior)") {
        // Multi-term: 'oct sun' matches 'October 18 Sunday Morning'
        let match = FuzzyMatcher.score(pattern: "oct sun", in: "October 18 Sunday Morning")
        try assertTrue(match != nil, "Expected 'oct sun' to match")

        // Multi-term where one term does not match
        let nonMatch = FuzzyMatcher.score(pattern: "oct monday", in: "October 18 Sunday Morning")
        try assertTrue(nonMatch == nil, "Expected 'oct monday' not to match")
    }

    await suite.run(name: "FuzzyMatcher scores exact and prefix matches higher") {
        let exact = FuzzyMatcher.score(pattern: "Sunday", in: "Sunday")!
        let prefix = FuzzyMatcher.score(pattern: "Sunday", in: "Sunday Morning")!
        let contains = FuzzyMatcher.score(pattern: "Sunday", in: "Great Sunday Morning")!
        let scattered = FuzzyMatcher.score(pattern: "Sunday", in: "Some Unique New Day Announcements Yet")!

        try assertTrue(exact.score > prefix.score, "Exact match score (\(exact.score)) should exceed prefix score (\(prefix.score))")
        try assertTrue(prefix.score > contains.score, "Prefix score (\(prefix.score)) should exceed contains score (\(contains.score))")
        try assertTrue(contains.score > scattered.score, "Contains score (\(contains.score)) should exceed scattered score (\(scattered.score))")
    }

    // MARK: - Sorting Tests

    await suite.run(name: "PPPlaylistNode sorts by Date descending (newest at the top)") {
        let p1 = PPPlaylistNode(uuid: "1", name: "2026-10-04 Sunday Morning")
        let p2 = PPPlaylistNode(uuid: "2", name: "2026-10-18 Sunday Morning")
        let p3 = PPPlaylistNode(uuid: "3", name: "2026-10-11 Sunday Morning")
        let p4 = PPPlaylistNode(uuid: "4", name: "Default Playlist") // No date

        let nodes = [p1, p2, p3, p4]
        let sorted = nodes.sortedTree(by: .date, order: .descending)

        // Newest (Oct 18) must be first, then Oct 11, then Oct 4, then undated
        try assertTrue(sorted[0].id == "2", "Expected Oct 18 first, got \(sorted[0].name)")
        try assertTrue(sorted[1].id == "3", "Expected Oct 11 second, got \(sorted[1].name)")
        try assertTrue(sorted[2].id == "1", "Expected Oct 4 third, got \(sorted[2].name)")
        try assertTrue(sorted[3].id == "4", "Expected undated fourth, got \(sorted[3].name)")
    }

    await suite.run(name: "PPPlaylistNode sorts by Date ascending (oldest at the top)") {
        let p1 = PPPlaylistNode(uuid: "1", name: "2026-10-04 Sunday Morning")
        let p2 = PPPlaylistNode(uuid: "2", name: "2026-10-18 Sunday Morning")
        let p3 = PPPlaylistNode(uuid: "3", name: "2026-10-11 Sunday Morning")

        let nodes = [p1, p2, p3]
        let sorted = nodes.sortedTree(by: .date, order: .ascending)

        try assertTrue(sorted[0].id == "1", "Expected Oct 4 first")
        try assertTrue(sorted[1].id == "3", "Expected Oct 11 second")
        try assertTrue(sorted[2].id == "2", "Expected Oct 18 third")
    }

    await suite.run(name: "PPPlaylistNode sorts by Name ascending and descending") {
        let pA = PPPlaylistNode(uuid: "A", name: "Alpha Service")
        let pB = PPPlaylistNode(uuid: "B", name: "Beta Service")
        let pC = PPPlaylistNode(uuid: "C", name: "Gamma Service")

        let nodes = [pB, pC, pA]
        let sortedAsc = nodes.sortedTree(by: .name, order: .ascending)
        try assertTrue(sortedAsc.map(\.name) == ["Alpha Service", "Beta Service", "Gamma Service"], "Expected A to Z")

        let sortedDesc = nodes.sortedTree(by: .name, order: .descending)
        try assertTrue(sortedDesc.map(\.name) == ["Gamma Service", "Beta Service", "Alpha Service"], "Expected Z to A")
    }

    await suite.run(name: "PPPlaylistNode sorts groups and their children recursively") {
        let child1 = PPPlaylistNode(uuid: "c1", name: "2026-10-04 Service")
        let child2 = PPPlaylistNode(uuid: "c2", name: "2026-10-18 Service")
        let groupOctober = PPPlaylistNode(uuid: "g1", name: "October", fieldType: "group", children: [child1, child2])

        let childSept = PPPlaylistNode(uuid: "c3", name: "2026-09-20 Service")
        let groupSeptember = PPPlaylistNode(uuid: "g2", name: "September", fieldType: "group", children: [childSept])

        let rootNodes = [groupSeptember, groupOctober]
        let sorted = rootNodes.sortedTree(by: .date, order: .descending)

        // October group contains newer playlist (Oct 18) than September, so October should be first
        try assertTrue(sorted[0].id == "g1", "October group should be first")
        try assertTrue(sorted[1].id == "g2", "September group should be second")

        // Inside October group, Oct 18 should be before Oct 4
        let octChildren = sorted[0].children ?? []
        try assertTrue(octChildren[0].id == "c2", "Oct 18 should be first child")
        try assertTrue(octChildren[1].id == "c1", "Oct 4 should be second child")
    }

    // MARK: - Search & Filter Tests

    await suite.run(name: "PPPlaylistNode.search filters while typing and sorts newest first by default") {
        let p1 = PPPlaylistNode(uuid: "1", name: "2026-10-04 Sunday Morning")
        let p2 = PPPlaylistNode(uuid: "2", name: "2026-10-18 Sunday Morning")
        let p3 = PPPlaylistNode(uuid: "3", name: "2026-10-11 Sunday Evening")
        let p4 = PPPlaylistNode(uuid: "4", name: "2026-10-16 Friday Youth")

        let nodes = [p1, p2, p3, p4]

        // Search "sun"
        let sunMatches = PPPlaylistNode.search(nodes: nodes, query: "sun", sortOption: .dateDescending)
        try assertTrue(sunMatches.count == 3, "Expected 3 matches for 'sun', got \(sunMatches.count)")
        // Verify default sort is newest first: Oct 18, then Oct 11, then Oct 4
        try assertTrue(sunMatches[0].node.id == "2", "Expected Oct 18 first")
        try assertTrue(sunMatches[1].node.id == "3", "Expected Oct 11 second")
        try assertTrue(sunMatches[2].node.id == "1", "Expected Oct 4 third")

        // Search "youth"
        let youthMatches = PPPlaylistNode.search(nodes: nodes, query: "youth", sortOption: .dateDescending)
        try assertTrue(youthMatches.count == 1, "Expected 1 match for 'youth'")
        try assertTrue(youthMatches[0].node.id == "4", "Expected Friday Youth match")
    }

    await suite.run(name: "PPPlaylistNode.search matches folder path breadcrumbs") {
        let child = PPPlaylistNode(uuid: "c1", name: "Morning Service")
        let folder = PPPlaylistNode(uuid: "f1", name: "Special Events", fieldType: "group", children: [child])

        let matches = PPPlaylistNode.search(nodes: [folder], query: "special", sortOption: .dateDescending)
        try assertTrue(matches.count == 1, "Expected search by folder name to find child playlist")
        try assertTrue(matches[0].folderPath == "Special Events", "Expected folder path breadcrumb")
    }
}
