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
            CommandGroup(replacing: .importExport) {
                Button("AirDrop Package…") {
                    modelState.wrappedValue.beginAirDrop()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(modelState.wrappedValue.plan == nil || modelState.wrappedValue.plan?.resolvedCount == 0 || modelState.wrappedValue.isExporting)

                Button("Save Package to Disk…") {
                    modelState.wrappedValue.beginExport()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(modelState.wrappedValue.plan == nil || modelState.wrappedValue.plan?.resolvedCount == 0 || modelState.wrappedValue.isExporting)
            }
        }
    }
}
