import SwiftUI

@main
struct ProPackApp: App {
    private var modelState = State(initialValue: AppModel())

    var body: some Scene {
        Window("ProPack", id: "main") {
            ContentView()
                .environment(modelState.wrappedValue)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
