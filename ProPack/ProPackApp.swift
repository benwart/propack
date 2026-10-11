import SwiftUI

@main
struct ProPackApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("ProPack", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
