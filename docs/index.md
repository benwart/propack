# ProPack

**ProPack** is a lightweight, high-performance macOS utility built natively in Swift and SwiftUI. It connects to an active ProPresenter instance, inspects selected service playlists, locates the underlying `.pro` files across local libraries, and exports a clean `.zip` archive containing the presentations, active arrangements, and an extensive metadata `manifest.json`.

---

## Highlights

- **Zero External Runtime Dependencies**: Does not require Python, Node.js, or external CLI binaries. Runs purely on native macOS technologies (`URLSession`, `Foundation.Process`, and Apple's `/usr/bin/ditto`).
- **Automatic Port Discovery**: Resolves ProPresenter's random ephemeral HTTP API port (50000–65000) using local socket inspection via `/usr/sbin/lsof` and verifies identity against `/version`.
- **Intelligent Library Locating**: Overcomes ProPresenter's lack of raw file streams by dynamically discovering the active library path and using a multi-tiered search strategy (API path $\to$ filename $\to$ Protobuf byte-level UUID scan).
- **Service & Arrangement Preserved**: Captures playlist ordering, header markers, slide group color and notes, and active arrangement selections per song.
- **Fast, Clean Archiving**: Packages the staging bundle using `/usr/bin/ditto -c -k --sequesterRsrc --keepParent` ensuring valid PKZip archives that respect macOS resource forks.

---

## Quick Navigation

- [Getting Started](getting-started.md): Installation and first-time setup guide.
- [Architecture](architecture.md): High-level system design and execution workflow.
- [Technical Specifications](specs/port-detection.md): Deep-dive into port discovery, library resolution, and manifest generation.
- [Development](development.md): Project build instructions and testing workflow.
