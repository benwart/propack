# Development & Contributing

## Building the App

### Requirements
- macOS 14.0 or newer
- Xcode 15 or 16+
- Swift 6.0+

### Automated CLI Build (`make`)
You can build the full installable `.app` bundle from the terminal without launching Xcode:
```bash
# Compile, assemble, and sign ProPack.app into dist/
make app

# Or install it directly into /Applications:
make install
```

### Compiling with Xcode
1. Open `ProPack.xcodeproj` in Xcode:
   ```bash
   open ProPack.xcodeproj
   ```
2. Build and run via `Product ▸ Run` (`Cmd + R`).

### Command-Line Compilation Check
You can verify compilation of the application files with the Swift compiler:
```bash
swiftc -swift-version 6 \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  -module-cache-path .build/modcache \
  -typecheck \
  ProPack/*.swift
```

---

## Local Testing with Mock Server

ProPack includes a standalone mock server and test harness to simulate ProPresenter without needing the full application running:

1. **Launch the Mock API**:
   ```bash
   python3 -m http.server 58123  # or run the custom test fixture
   ```
2. **Run E2E Verification**:
   The test script validates port detection, presentation metadata fetch, multi-tiered file location, and `.zip` archive creation using `ditto`.

---

## Documentation Generator Guide

### Generating HTML Docs with MkDocs & uv

ProPack docs are authored in Markdown and configured for [MkDocs](https://www.mkdocs.org/) with the **Material for MkDocs** theme (`mkdocs-material`) featuring **dark mode by default**.

Python tool dependencies are managed via **[uv](https://github.com/astral-sh/uv)** (specified in `.tool-versions` and `pyproject.toml`). You do not need to install Python or MkDocs globally.

#### Running the Development Server

To preview the documentation locally with hot reloading:

```bash
make docs-serve
# Or directly:
uv run --group docs mkdocs serve
```

Open `http://127.0.0.1:8000` in your web browser.

#### Building Static HTML

To compile the documentation into a standalone static site in `site/`:

```bash
make docs
# Or directly:
uv run --group docs mkdocs build --strict
```

---

## Notes on Swift Documentation Generators

For Apple ecosystem projects:
- **Apple Swift-DocC**: Apple's native documentation compiler (`docc`). It is designed for framework and library API symbol graphs extracted during compiler builds (`swift package generate-documentation` or Xcode's `Product ▸ Build Documentation`). Because ProPack is a standalone macOS application and user utility (rather than a public SDK/library), general-purpose documentation engines like **MkDocs Material** provide a superior structure for user guides, technical specifications, and end-to-end architectural overviews.
