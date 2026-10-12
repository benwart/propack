import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage("proPresenterPort") private var port: Int = 0
    @AppStorage("autoConnectOnLaunch") private var autoConnectOnLaunch: Bool = true
    @AppStorage("defaultSongConflictPolicy") private var defaultSongPolicy: String = SongConflictPolicy.rename.rawValue
    @AppStorage("defaultPlaylistConflictPolicy") private var defaultPlaylistPolicy: String = PlaylistConflictPolicy.keepBoth.rawValue
    @AppStorage("defaultIncludeMedia") private var defaultIncludeMedia: Bool = true
    @AppStorage("customMediaDirectory") private var customMediaDirectory: String = ""

    private let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    private let buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            librariesTab
                .tabItem { Label("Paths & Network", systemImage: "folder") }
                .tag(1)

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 520, height: 380)
        .padding(20)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Import Defaults") {
                Picker("Song Conflict:", selection: $defaultSongPolicy) {
                    ForEach(SongConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy.rawValue)
                    }
                }
                .help("Default conflict behavior when an imported presentation already exists in the local library")

                Picker("Playlist Conflict:", selection: $defaultPlaylistPolicy) {
                    ForEach(PlaylistConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy.rawValue)
                    }
                }
                .help("Default conflict behavior when an imported playlist already exists")
            }

            Section("Export Defaults") {
                Toggle("Automatically bundle referenced media files", isOn: $defaultIncludeMedia)
                    .help("Include background videos, images, and audio tracks in exported packages by default")
            }

            Section("Startup") {
                Toggle("Auto-connect to ProPresenter on launch", isOn: $autoConnectOnLaunch)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Paths Tab

    private var librariesTab: some View {
        Form {
            Section("ProPresenter Network API") {
                LabeledContent("API Port:") {
                    HStack {
                        TextField("Port", value: $port, format: .number.grouping(.never))
                            .frame(width: 90)
                            .textFieldStyle(.roundedBorder)
                        Text("(0 for auto-detect)").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Media Directory") {
                LabeledContent("Save Imported Media To:") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(customMediaDirectory.isEmpty ? "Default: ~/Documents/ProPresenter/Media" : customMediaDirectory)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack {
                            Button("Choose Folder…") {
                                let panel = NSOpenPanel()
                                panel.title = "Select Folder for Imported Media"
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    customMediaDirectory = url.path
                                }
                            }
                            if !customMediaDirectory.isEmpty {
                                Button("Reset to Default") {
                                    customMediaDirectory = ""
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            if let iconImage = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }

            VStack(spacing: 4) {
                Text("ProPack").font(.title.bold())
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("ProPresenter Playlist Pack Exporter & Importer for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()

            HStack(spacing: 16) {
                Button("Help Documentation…") {
                    HelpService.openInBrowser()
                }
                Button("Visit GitHub") {
                    if let url = URL(string: "https://github.com/benwart/propack") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer()
        }
    }
}
