import AppKit
import SwiftUI

@MainActor
private struct ConnectionSetupPreviewHost: View {
    @Environment(AppModel.self) private var model
    private var portState = State(initialValue: 51664)

    var body: some View {
        ScrollView {
            ConnectionSetupView(port: portState.projectedValue)
                .padding(24)
        }
    }
}

@MainActor
enum ScreenshotCapture {
    static func run(model: AppModel, outputDir: URL) async {
        print("==> Starting automated screenshot capture...")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // 1. Connect to ProPresenter
        print("--> Connecting to ProPresenter...")
        _ = await model.connectOnLaunch(savedPort: 51664)
        
        // Wait for connection and playlists
        for _ in 0..<30 {
            if model.connection.isConnected && !model.playlists.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // 2. Select first playlist (2026-10-11 Sarah)
        if let firstID = model.playlists.first?.id {
            print("--> Selecting playlist \(firstID)...")
            model.selectedPlaylistID = firstID
        }

        // Wait for plan to resolve
        for _ in 0..<30 {
            if let plan = model.plan, plan.resolvedCount > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // Allow SwiftUI layout to stabilize and render all views
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // 3. Capture Main Window (Playlist Detail)
        if let mainWindow = NSApplication.shared.windows.first(where: {
            $0.isVisible && ($0.title.contains("–") || $0.identifier?.rawValue == "main")
        }) ?? NSApplication.shared.mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
            mainWindow.setContentSize(NSSize(width: 1140, height: 720))
            mainWindow.center()
            mainWindow.display()
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            let dest = outputDir.appendingPathComponent("01-playlist-detail.png")
            capture(window: mainWindow, to: dest)
        }

        // 4. Seed Transfer History and capture TransferHistoryView
        print("--> Capturing Transfer History...")
        TransferHistoryStore.shared.clear()
        TransferHistoryStore.shared.record(TransferRecord(
            type: .airdrop,
            playlistName: "2026-10-11 Sarah",
            presentationCount: 5,
            mediaCount: 0,
            filePath: nil,
            fileSizeBytes: 148_920,
            status: .completed,
            detail: "AirDropped directly to Sanctuary iMac"
        ))
        TransferHistoryStore.shared.record(TransferRecord(
            type: .export,
            playlistName: "2026-10-04 David",
            presentationCount: 5,
            mediaCount: 0,
            filePath: "~/Desktop/2026-10-04 David.propack",
            fileSizeBytes: 142_310,
            status: .completed,
            detail: "Stand-alone archive created with manifest.json"
        ))
        TransferHistoryStore.shared.record(TransferRecord(
            type: .import,
            playlistName: "2026-09-27 Chris",
            presentationCount: 4,
            mediaCount: 0,
            filePath: "~/Downloads/2026-09-27 Chris.propack",
            fileSizeBytes: 139_840,
            status: .completed,
            detail: "Imported into Default library (4 songs updated)"
        ))

        let historyWindow = makeWindow(
            title: "Transfer History & Audit Log",
            content: TransferHistoryView(),
            size: NSSize(width: 760, height: 500)
        )
        historyWindow.display()
        try? await Task.sleep(nanoseconds: 400_000_000)
        capture(window: historyWindow, to: outputDir.appendingPathComponent("02-transfer-history.png"))
        historyWindow.orderOut(nil)

        // 5. Create a real package and capture ImportSheetView
        print("--> Capturing Import Workflow...")
        if let plan = model.plan {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let pkgURL = tempDir.appendingPathComponent("2026-10-11 Sarah.propack")
            
            _ = try? await ExportService().export(
                plan: plan,
                to: pkgURL,
                includeMedia: false,
                includeThemes: true,
                includeFonts: true
            )
            
            if FileManager.default.fileExists(atPath: pkgURL.path) {
                model.openPackageForImport(url: pkgURL)
                for _ in 0..<30 {
                    if case .ready = model.importState { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                
                let importWindow = makeWindow(
                    title: "Import Playlist Package",
                    content: ImportSheetView().environment(model),
                    size: NSSize(width: 780, height: 720)
                )
                importWindow.display()
                try? await Task.sleep(nanoseconds: 400_000_000)
                capture(window: importWindow, to: outputDir.appendingPathComponent("03-import-workflow.png"))
                importWindow.orderOut(nil)
            }
        }

        // 6. Capture Connection Settings
        print("--> Capturing Connection Settings...")
        let connectionWindow = makeWindow(
            title: "ProPresenter Network Connection",
            content: ConnectionSetupPreviewHost().environment(model),
            size: NSSize(width: 640, height: 600)
        )
        connectionWindow.display()
        try? await Task.sleep(nanoseconds: 400_000_000)
        capture(window: connectionWindow, to: outputDir.appendingPathComponent("04-connection-settings.png"))
        connectionWindow.orderOut(nil)

        // 7. Capture Help Viewer
        print("--> Capturing Help Viewer...")
        let helpWindow = makeWindow(
            title: "ProPack Help & Documentation",
            content: HelpWindowView(),
            size: NSSize(width: 900, height: 640)
        )
        helpWindow.display()
        try? await Task.sleep(nanoseconds: 400_000_000)
        capture(window: helpWindow, to: outputDir.appendingPathComponent("05-help-viewer.png"))
        helpWindow.orderOut(nil)

        print("==> All screenshots captured successfully!")
        try? await Task.sleep(nanoseconds: 200_000_000)
        exit(0)
    }

    private static func makeWindow<V: View>(title: String, content: V, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private static func capture(window: NSWindow, to url: URL) {
        window.display()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", "\(window.windowNumber)", url.path]
        try? process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: url.path),
           let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
           (attr[.size] as? Int64 ?? 0) > 0 {
            print("  ✓ Saved \(url.lastPathComponent) (\(attr[.size] ?? 0) bytes)")
            return
        }

        // Fallback to cacheDisplay if screencapture didn't work
        guard let targetView = window.contentView?.superview ?? window.contentView else { return }
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        targetView.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("  ✓ Saved \(url.lastPathComponent) (\(data.count) bytes)")
        }
    }
}
