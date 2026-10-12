import Foundation

@MainActor
func runMediaLocatorTests() async {
    let suite = TestSuite.shared

    await suite.run(name: "MediaLocator.kindClassification") {
        try assertEqual(MediaAsset.Kind.from(extension: "mp4"), .video)
        try assertEqual(MediaAsset.Kind.from(extension: "mov"), .video)
        try assertEqual(MediaAsset.Kind.from(extension: "png"), .image)
        try assertEqual(MediaAsset.Kind.from(extension: "jpg"), .image)
        try assertEqual(MediaAsset.Kind.from(extension: "mp3"), .audio)
        try assertEqual(MediaAsset.Kind.from(extension: "wav"), .audio)
        try assertEqual(MediaAsset.Kind.from(extension: "txt"), .other)
    }

    await suite.run(name: "MediaLocator.extractPotentialMediaPaths from raw data") {
        let fakeProtobuf = """
        \u{08}\u{01}\u{12}\u{20}SomePresentationData\u{1A}\u{30}/Users/church/Documents/ProPresenter/Media/Background Loop.mp4\u{22}\u{10}IntroSlide.jpeg\u{00}
        """
        let data = fakeProtobuf.data(using: .ascii)!
        let extracted = MediaLocator.extractPotentialMediaPaths(from: data)

        try assertTrue(extracted.contains("/Users/church/Documents/ProPresenter/Media/Background Loop.mp4"))
        try assertTrue(extracted.contains("IntroSlide.jpeg"))
    }
}
