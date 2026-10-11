# ProPack: ProPresenter Playlist Pack Exporter

Native macOS utility (macOS 14+ / 15+, SwiftUI) with **zero external runtime dependencies** that connects to a local ProPresenter instance, lets you select a playlist, and exports a standalone `.zip` archive containing the source `.pro` presentation files, active arrangement mappings, slide group metadata, and a comprehensive `manifest.json`.

---

## Key Features

1. **Zero External Runtime Dependencies**
   - Built entirely in native Swift / SwiftUI using `URLSession` for local REST communications and Apple's native `/usr/bin/ditto` for PKZip archive creation.
   - No Python, Node.js, or external CLI binaries required at runtime.

2. **Ephemeral Port Detection & Robust Fallback**
   - ProPresenter assigns random ephemeral ports (typically `50000–65000`).
   - Auto-detects listening ports via `/usr/sbin/lsof -nP -a -p <PID> -iTCP -sTCP:LISTEN` by finding ProPresenter processes via `NSWorkspace`.
   - Probes listening ports concurrently against `/version` to verify the active ProPresenter API.
   - Includes manual port input with `@AppStorage` persistence, instant "Test Connection" status indicator, and guided setup instructions.

3. **Dynamic Library Path Discovery**
   - Resolves library locations by querying `GET /v1/presentation/{uuid}`, extracting `presentation_path` directly from the active library.
   - Multi-tiered resolution fallback:
     1. Exact `presentation_path` reported by API.
     2. Case-insensitive filename matching across detected/default library folders (`~/Documents/ProPresenter/Libraries/` and `~/Library/Application Support/RenewedVision/ProPresenter/Libraries/`).
     3. Byte-level UUID scan within Protobuf `.pro` files to disambiguate or locate renamed presentations.
   - Fallback directory picker (`NSOpenPanel`) with persistent security-scoped bookmark support.

4. **Playlist Packaging & Manifest**
   - Hierarchical playlist selector (`OutlineGroup` supporting folders and playlists).
   - Generates a standalone `.zip` using `/usr/bin/ditto -c -k --sequesterRsrc --keepParent`.
   - Produces a companion `manifest.json` detailing:
     - Export timestamp & generator version.
     - ProPresenter host & API version.
     - Playlist title, UUID, and item index order.
     - Presentation UUIDs, arrangements (active UUID + name), slide group metadata, SHA-256 hashes, file sizes, and match methods.

---

## Project Structure

```
propack/
├── Config/
│   ├── Info.plist                # ATS configuration allowing local HTTP API calls
│   └── ProPack.entitlements      # Hardened runtime & process inspection permissions
├── ProPack/
│   ├── ProPackApp.swift          # App entry point & window scene configuration
│   ├── AppModel.swift            # MainActor observable state machine (connection, playlists, export)
│   ├── ContentView.swift         # SwiftUI interface (sidebar, preview table, connection setup, export bar)
│   ├── ProPresenterClient.swift  # URLSession REST client & tolerant Codable models
│   ├── PortDetector.swift        # Process inspection (lsof) & port probing
│   ├── LibraryLocator.swift      # Resolves presentations to .pro files (API path, filename, byte scan)
│   ├── ExportService.swift       # Staging directory, manifest.json generator, and ditto archiving
│   └── ProcessRunner.swift       # Async non-blocking subprocess runner (concurrent stdout/stderr drains)
└── ProPack.xcodeproj/            # Xcode 16+ project (filesystem-synchronized group)
```

---

## Building & Running

### Requirements
- macOS 14.0 or newer
- Xcode 15 or 16+ with Swift 6 support

### In Xcode
1. Open `ProPack.xcodeproj` in Xcode.
2. Select the **ProPack** scheme and target **My Mac**.
3. Press `Cmd + R` to build and run.

---

## How to Use

1. **Enable Network in ProPresenter**:
   - In ProPresenter, go to **Settings** (or **Preferences**) ▸ **Network**.
   - Ensure **Enable Network** is toggled ON. Note the port number displayed.
2. **Launch ProPack**:
   - ProPack will automatically detect ProPresenter and connect to its port.
   - If not auto-detected, click the connection badge in the toolbar or enter the port number manually and click **Test Connection**.
3. **Select Playlist**:
   - Choose any playlist from the sidebar. ProPack will preview all items, slide groups, and resolved `.pro` files.
4. **Export**:
   - Click **Export...** (or press `Cmd + E`) and choose a destination. ProPack packages the presentations into a clean `.zip` archive alongside `manifest.json`.
