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
            CommandGroup(replacing: .appInfo) {
                Button("About ProPack") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: version,
                        .version: build
                    ])
                }
            }
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
            CommandGroup(replacing: .help) {
                HelpMenuCommands()
            }
        }

        Window("ProPack Help", id: "help") {
            HelpWindowView()
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 920, height: 660)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
private struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("ProPack Help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)

        Button("Open Help in Browser…") {
            HelpService.openInBrowser()
        }
    }
}

