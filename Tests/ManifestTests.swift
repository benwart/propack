import Foundation

@MainActor
func runManifestTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "Manifest.decodeFromJson snake_case keys") {
        let sampleJSON = """
        {
            "format": "propack",
            "format_version": 1,
            "exported_at": "2026-10-11T20:00:00Z",
            "generator": {
                "name": "ProPack",
                "version": "0.1.0"
            },
            "source": {
                "host_description": "Production Mac",
                "api_version": "v1",
                "platform": "macOS",
                "os_version": "14.5"
            },
            "playlist": {
                "uuid": "pl-1234",
                "name": "Sunday Morning"
            },
            "library_roots": [
                "/Users/test/Documents/ProPresenter/Libraries/Default"
            ],
            "summary": {
                "total_items": 1,
                "presentations": 1,
                "included": 1,
                "missing": 0,
                "unique_files": 1
            },
            "items": [
                {
                    "index": 0,
                    "playlist_item_uuid": "item-1",
                    "name": "Way Maker",
                    "type": "presentation",
                    "is_hidden": false,
                    "status": "included",
                    "presentation_uuid": "pres-way-maker",
                    "arrangement": {
                        "uuid": "arr-1",
                        "name": "Standard"
                    },
                    "match_method": "file_name",
                    "api_presentation_path": "/Libraries/Default/Way Maker.pro",
                    "file": {
                        "package_path": "presentations/Way Maker.pro",
                        "source_path": "/Users/test/Documents/ProPresenter/Libraries/Default/Way Maker.pro",
                        "size_bytes": 4096,
                        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                        "modified_at": "2026-10-11T19:00:00Z"
                    },
                    "groups": [
                        {
                            "name": "Verse 1",
                            "slide_count": 4,
                            "slide_labels": ["Slide 1", "Slide 2"]
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: sampleJSON)

        try assertEqual(manifest.format, "propack")
        try assertEqual(manifest.formatVersion, 1)
        try assertEqual(manifest.generator.name, "ProPack")
        try assertEqual(manifest.playlist.name, "Sunday Morning")
        try assertEqual(manifest.items.count, 1)

        let item = manifest.items[0]
        try assertEqual(item.name, "Way Maker")
        try assertEqual(item.status, .included)
        try assertEqual(item.file?.sizeBytes, 4096)
        try assertEqual(item.groups?.count, 1)
        try assertEqual(item.groups?[0].name, "Verse 1")

        // Now test re-encoding to verify roundtrip encoding
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let reencoded = try encoder.encode(manifest)

        let roundtrip = try decoder.decode(Manifest.self, from: reencoded)
        try assertEqual(roundtrip.playlist.uuid, "pl-1234")
        try assertEqual(roundtrip.items[0].file?.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
