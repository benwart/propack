# Getting Started

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- **Host Application**: ProPresenter 7.9+ (ProPresenter 7.16+ recommended with HTTP REST API enabled)
- **Architecture**: Universal (Apple Silicon arm64 & Intel x86_64)

---

## First-Time Configuration

Before ProPack can inspect playlists, ProPresenter's REST API must be active on your machine.

### 1. Enable Network API in ProPresenter

1. Open **ProPresenter**.
2. From the application menu, select **ProPresenter** ▸ **Settings…** (or press `Cmd + ,`).
3. Switch to the **Network** tab.
4. Toggle on **Enable Network**.
5. Note the assigned port number displayed next to the toggle (ProPresenter assigns a random ephemeral port, typically between `50000` and `65000`).

```
┌────────────────────────────────────────────────────────┐
│ Settings ▸ Network                                     │
├────────────────────────────────────────────────────────┤
│ [✓] Enable Network           Port: 58123               │
│                                                        │
│ [API Documentation]                                    │
└────────────────────────────────────────────────────────┘
```

### 2. Launch ProPack

1. Launch **ProPack.app**.
2. On startup, ProPack immediately queries local processes to locate ProPresenter's listening socket.
3. If successful, the toolbar status badge will switch to **Connected** with the active port number and ProPresenter version string.

### 3. Manual Connection & Troubleshooting

If ProPresenter is running with custom network restrictions or in a different sandbox:

1. Click the status badge in the top-left of the window, or look at the connection screen in the main panel.
2. Enter the port number directly into the **Port** field.
3. Click **Test Connection**.
4. Once verified, ProPack will persist this port in macOS `UserDefaults` (`@AppStorage`) for subsequent launches.

---

## Exporting Your First Playlist

1. **Select a Playlist**:
   In the left sidebar, navigate the playlist tree or use the fuzzy search bar to filter playlists in real time while typing. Sort playlists by date (default: newest at the top) or name (A–Z / Z–A) using the sort menu (`arrow.up.arrow.down`). You can also toggle between Tree View and Flat List. Click any playlist item to preview its contents.
2. **Review Presentations & Mappings**:
   ProPack will asynchronously query presentation metadata and match local `.pro` files.
   - **Green Checkmark**: The `.pro` file was discovered and verified on disk.
   - **Orange Warning**: The presentation exists in the playlist, but no matching file was found in your library directories.
3. **Select Library Folder (If Needed)**:
   If presentations are missing, click **Choose Folder…** in the bottom bar to direct ProPack to your ProPresenter Libraries directory (e.g., `~/Documents/ProPresenter/Libraries`).
4. **Trigger Export**:
   Click **Export…** (or press `Cmd + E`). Select a destination directory and filename. ProPack creates the standalone `.zip` package and offers a **Show in Finder** shortcut upon completion.
