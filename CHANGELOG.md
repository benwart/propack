## [1.1.0](https://github.com/benwart/propack/compare/v1.0.1...v1.1.0) (2026-10-16)

### Features

* add arrangement tracking, color-coded slide group badges, and visual tour ([fed07e3](https://github.com/benwart/propack/commit/fed07e3e046f1bf349402c9d7204cd74c4a7336e))
* add playlist filtering, sorting, and search capabilities to the sidebar ([492b18c](https://github.com/benwart/propack/commit/492b18cfe4b951f03dea0223ab2132cf0888cdde))
* **locator:** detect ProPresenter workspaces, Audience Look themes, and custom fonts ([022d114](https://github.com/benwart/propack/commit/022d1145507934708a5556e2855f0cbae763ff4f))
* **transfer:** bundle and restore Audience Look themes and fonts in .propack archives ([86fb17a](https://github.com/benwart/propack/commit/86fb17a340ad05da88069434b096a48d2c3ed58c))
* **ui:** add theme and font export toggles and import destination previews ([7bf2735](https://github.com/benwart/propack/commit/7bf27356dfdb7143e6f56215f30c1045e01f8f68))

### Bug Fixes

* **release:** downgrade conventional-changelog-conventionalcommits to v9 for semantic-release compatibility ([cf4e6e6](https://github.com/benwart/propack/commit/cf4e6e69a4040548e629406d5da45045ce9e3a3f))

## [1.0.1](https://github.com/benwart/propack/compare/v1.0.0...v1.0.1) (2026-10-12)

### Bug Fixes

* **concurrency:** resolve nonisolated WKNavigationDelegate requirement in HelpNavDelegate ([923f587](https://github.com/benwart/propack/commit/923f58701c158d4699567d1c8f07acf3e688019f))

## 1.0.0 (2026-10-12)

### Features

* **branding:** add ProPack macOS app icon, asset catalog, and UI header badge ([8304012](https://github.com/benwart/propack/commit/830401235a8da2e5cd0e65362aebc280f76f0fe9))
* **build:** add make uninstall target to remove app and unregister file associations ([24f04a6](https://github.com/benwart/propack/commit/24f04a6942ec640ee7ebd85de9cc7ab6e54db9e1))
* **build:** add Makefile and build script for automated CLI app bundle builds ([8e61ac7](https://github.com/benwart/propack/commit/8e61ac72c5093e34268ae5843766311e5684d422))
* **core:** implement API client, port detection, library discovery, and export service ([dbbe2ac](https://github.com/benwart/propack/commit/dbbe2acf3ddef8dc4acd2e31ae734c428411750a))
* **dmg:** add custom branded background, logo, and drag-and-drop installer layout to DMG ([e2fc2b7](https://github.com/benwart/propack/commit/e2fc2b79c6372f13970400a14ac2dfbe9c402e8f))
* **export:** add direct AirDrop support with zero-cruft temporary lifecycle ([75b521c](https://github.com/benwart/propack/commit/75b521c152b3145b82da88aeb907e7233b56b3f4))
* **history:** add transfer history and audit log for package operations ([b0573c8](https://github.com/benwart/propack/commit/b0573c8573f7cc478ed2e331262b5317bf686ac7))
* **import:** add package import with library, playlist, and group conflict resolution ([947afaf](https://github.com/benwart/propack/commit/947afaf44cc337e5a7f29c19917003f0e7bb641c))
* **media:** add media asset detection, bundling, and import extraction ([a16c6a3](https://github.com/benwart/propack/commit/a16c6a39fae1b6fcd699ea44d213cdd3cbcfa8b3))
* **package:** register .propack custom document type for return AirDrop auto-launch ([5de2811](https://github.com/benwart/propack/commit/5de2811a78e06c874dca836341157aecd6b689e4))
* **release:** add Node semantic-release, dynamic versioning, DMG installer, and About dialog ([9bce345](https://github.com/benwart/propack/commit/9bce3452d01ac8a0dc233b5a0eea5a666a10d95d))
* **settings:** add native macOS application settings window (Cmd+,) ([8c1298f](https://github.com/benwart/propack/commit/8c1298fdbec5b16a2454fc3c88c5b25ffcdd1927))
* **ui:** add SwiftUI interface, state management, and setup guidance ([763dc4e](https://github.com/benwart/propack/commit/763dc4e0831535c90cdd10d40cb65914586807b9))

### Bug Fixes

* **branding:** correct icon orientation to upright ([2f79eb7](https://github.com/benwart/propack/commit/2f79eb735b7d85a1e1b225b5b1afd985de674789))
* **branding:** simplify app icon with clean box and distinct warm orange gradient ([5712f8d](https://github.com/benwart/propack/commit/5712f8d2dedb788d0e1a16013069879569741e06))
* **branding:** use clean transparent background for app icon, logo, and favicons ([51b6696](https://github.com/benwart/propack/commit/51b6696aeeebd6162d3d22d18d914ea16c434340))
* **build:** refresh LaunchServices and Dock icon cache on make install ([c79efde](https://github.com/benwart/propack/commit/c79efde0f6a197b0d0c293a729fad7ef1539b51d))
* **ci:** remove pip cache requirement in setup-python action ([6e110e8](https://github.com/benwart/propack/commit/6e110e89c2eefe54c9a3d5253e6cb81c89efc596))
* **concurrency:** annotate SwiftUI views with @MainActor for strict concurrency compatibility ([d40562c](https://github.com/benwart/propack/commit/d40562c221e54ec7353ce0a533b267c2a351a6cb))
* **concurrency:** annotate WKNavigationDelegate and Help commands with @MainActor ([d698354](https://github.com/benwart/propack/commit/d6983540e8b829bae1610e403d402b65a5f112e5))
* **port-detector:** detect ProPresenter Helper network processes and listening sockets ([51330b7](https://github.com/benwart/propack/commit/51330b70143d417b2fa4eca4dba7e62171b7c8ec))
