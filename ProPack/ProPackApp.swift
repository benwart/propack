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

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in application.windows {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let idx = CommandLine.arguments.firstIndex(of: "--capture-screenshots") {
            let outPath = (idx + 1 < CommandLine.arguments.count) ? CommandLine.arguments[idx + 1] : "docs/assets/screenshots"
            let outURL = URL(fileURLWithPath: outPath)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let model = self.model {
                    await ScreenshotCapture.run(model: model, outputDir: outURL)
                }
            }
        }
    }
}

@main
struct ProPackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var modelState = State(initialValue: AppModel())

    var body: some Scene {
        let initialSize = LayoutPreferences().windowSize
        Window("ProPack", id: "main") {
            ContentView()
                .environment(modelState.wrappedValue)
                .frame(minWidth: CGFloat(LayoutDefaults.minWindowWidth), minHeight: CGFloat(LayoutDefaults.minWindowHeight))
                .onOpenURL { url in
                    modelState.wrappedValue.openPackageForImport(url: url)
                }
                .onAppear {
                    appDelegate.model = modelState.wrappedValue
                }
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
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

