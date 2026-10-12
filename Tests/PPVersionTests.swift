import Foundation

@MainActor
func runPPVersionTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "PPVersion.decodeFromJSON standard response") {
        let json = """
        {
            "name": "ProPresenter",
            "host_description": "ProPresenter 7.16.2",
            "api_version": "v1",
            "platform": "macOS",
            "os_version": "14.5.0"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(PPVersion.self, from: json)

        try assertEqual(decoded.name, "ProPresenter")
        try assertEqual(decoded.hostDescription, "ProPresenter 7.16.2")
        try assertEqual(decoded.apiVersion, "v1")
        try assertEqual(decoded.platform, "macOS")
        try assertEqual(decoded.osVersion, "14.5.0")
        try assertTrue(decoded.looksLikeProPresenter)
        try assertEqual(decoded.displayString, "ProPresenter 7.16.2 · API v1")
    }

    await suite.run(name: "PPVersion.looksLikeProPresenter without apiVersion") {
        let v = PPVersion(
            name: "ProPresenter",
            platform: "macOS",
            osVersion: nil,
            hostDescription: "ProPresenter Booth Mac",
            apiVersion: nil
        )
        try assertTrue(v.looksLikeProPresenter)
    }

    await suite.run(name: "PPVersion.looksLikeProPresenter non-ProPresenter") {
        let v = PPVersion(
            name: "Apache",
            platform: "Linux",
            osVersion: nil,
            hostDescription: "Ubuntu Web Server",
            apiVersion: nil
        )
        try assertFalse(v.looksLikeProPresenter)
    }

    await suite.run(name: "PPVersion.displayString fallback") {
        let v = PPVersion(
            name: nil,
            platform: nil,
            osVersion: nil,
            hostDescription: nil,
            apiVersion: nil
        )
        try assertEqual(v.displayString, "ProPresenter")
    }
}
