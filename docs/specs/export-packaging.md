# Technical Specification: Export & Packaging

The export pipeline stages the resolved presentation files, constructs a structured `manifest.json`, and invokes macOS `/usr/bin/ditto` to produce a compressed `.zip` package.

---

## Package Directory Structure

Before compression, `ExportService` stages files into an isolated temporary directory:

```
ProPack-<UUID>/
└── <PlaylistName>/
    ├── manifest.json
    └── Presentations/
        ├── Default/
        │   ├── Song A.pro
        │   └── Song B.pro
        └── Hymns/
            └── Song C.pro
```

- **Deduplication**: If a song is repeated in the playlist (e.g., an opening song reused at the close, or used twice with different arrangements), the source `.pro` file is copied only once.
- **Path Normalization**: Presentation files retain their relative subfolder paths (e.g. `Presentations/Default/...`) matching their parent library structure.

---

## Compression via `/usr/bin/ditto`

ProPack executes Apple's native `/usr/bin/ditto` utility using `Foundation.Process`:

```bash
/usr/bin/ditto -c -k --sequesterRsrc --keepParent <sourceDir> <destination.zip>
```

### Argument Details

| Flag | Purpose |
|---|---|
| `-c` | Creates an archive. |
| `-k` | Specifies PKZip format instead of CPIO. |
| `--sequesterRsrc` | Sequesters Mac OS resource forks and HFS metadata into `__MACOSX/` directories, ensuring clean cross-platform extraction. |
| `--keepParent` | Embeds the top-level `<PlaylistName>` directory inside the archive root so extracting does not scatter files across the destination folder. |

---

## The `manifest.json` Specification

The companion `manifest.json` file records all metadata about the export session.

### Schema Example

```json
{
  "format": "propack",
  "format_version": 1,
  "exported_at": "2026-10-11T21:25:06Z",
  "generator": {
    "name": "ProPack",
    "version": "0.1.0"
  },
  "source": {
    "host_description": "ProPresenter 7.16",
    "api_version": "v1",
    "platform": "mac",
    "os_version": "15.0"
  },
  "playlist": {
    "name": "Sunday AM Service",
    "uuid": "PL1-ABCD-1234"
  },
  "library_roots": [
    "/Users/username/Documents/ProPresenter/Libraries"
  ],
  "summary": {
    "total_items": 5,
    "presentations": 4,
    "included": 3,
    "missing": 1,
    "unique_files": 2
  },
  "items": [
    {
      "index": 0,
      "playlist_item_uuid": "I0-HEADER",
      "name": "Worship Set",
      "type": "header",
      "is_hidden": false,
      "status": "skipped"
    },
    {
      "index": 1,
      "playlist_item_uuid": "I1-SONG",
      "presentation_uuid": "11111111-AAAA-4BBB-8CCC-000000000001",
      "name": "Amazing Grace",
      "type": "presentation",
      "is_hidden": false,
      "status": "included",
      "match_method": "api_presentation_path",
      "api_presentation_path": "/Users/.../Libraries/Default/Amazing Grace.pro",
      "arrangement": {
        "name": "Short Arrangement",
        "uuid": "ARR-1-XYZ"
      },
      "file": {
        "package_path": "Presentations/Default/Amazing Grace.pro",
        "source_path": "/Users/.../Libraries/Default/Amazing Grace.pro",
        "size_bytes": 52410,
        "sha256": "46c696425c08ab8115d912bd1cad416305b1d2c8a4465384f18064d6628b6ff5",
        "modified_at": "2026-10-11T18:30:00Z"
      },
      "groups": [
        {
          "name": "Verse 1",
          "color": { "red": 0.0, "green": 0.5, "blue": 1.0, "alpha": 1.0 },
          "slide_count": 2,
          "slide_labels": ["V1a", "V1b"]
        },
        {
          "name": "Chorus",
          "color": null,
          "slide_count": 1,
          "slide_labels": ["C1"]
        }
      ]
    },
    {
      "index": 2,
      "playlist_item_uuid": "I2-MISSING",
      "presentation_uuid": "44444444-AAAA-4BBB-8CCC-000000000004",
      "name": "Special Music",
      "type": "presentation",
      "is_hidden": false,
      "status": "missing",
      "error": "No matching .pro file found in library roots"
    }
  ]
}
```

---

## Direct AirDrop Export & Zero-Cruft Lifecycle

ProPack supports direct transfer to iOS/macOS devices via Apple AirDrop without requiring the user to save files to disk first:

```
[User clicks AirDrop]
       │
       ▼
1. Create temporary directory: <temp>/ProPack/AirDrop/<UUID>/
       │
       ▼
2. Stage .pro files + manifest.json & compress via ditto to temporary .zip
       │
       ▼
3. Present native AirDrop sheet (NSSharingService.sendViaAirDrop)
       │
       ▼
4. User selects recipient device (e.g. iPhone) -> file transmitted
       │
       ▼
5. NSSharingServiceDelegate completes:
   - Success / Failure callback triggered
   - Temporary directory automatically purged (with 4s daemon safety buffer)
   - Zero file cruft left behind on user's Mac
```

### Cruft Prevention Guarantees

1. **Session Cleanup**: Once the AirDrop transfer finishes (or is cancelled by the user), the temporary archive folder is unlinked automatically.
2. **Cancellation Safety**: Cancelling mid-export immediately purges the staging directory.
3. **App Launch Purge**: `AirDropService.purgeAllTemporaryFiles()` runs on application startup to cleanly delete any orphaned files from unexpected crashes or abrupt process terminations.

