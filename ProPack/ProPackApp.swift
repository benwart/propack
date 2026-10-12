import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            model?.openPackageForImport(url: url)
        }
    }
}

@main
struct ProPackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var modelState = State(initialValue: AppModel())

    var body: some Scene {
        Window("ProPack", id: "main") {
            ContentView()
                .environment(modelState.wrappedValue)
                .frame(minWidth: 820, minHeight: 520)
                .onOpenURL { url in
                    modelState.wrappedValue.openPackageForImport(url: url)
                }
                .onAppear {
                    appDelegate.model = modelState.wrappedValue
                }
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .importExport) {
                Button("Import Package…") {
                    modelState.wrappedValue.choosePackageToImport()
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

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
