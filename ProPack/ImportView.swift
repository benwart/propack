import SwiftUI

struct ImportSheetView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 540, idealHeight: 620)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Playlist Package").font(.headline)
                Text("Review presentation conflict settings and target library before importing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.importState {
        case .idle:
            Color.clear
        case .inspecting:
            VStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                Text("Reading package archive…").foregroundStyle(.secondary)
            }
        case .ready(let package):
            packageView(package)
        case .importing(let package, _):
            packageView(package)
        case .finished(let result):
            finishedView(result)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                Text("Import Failed").font(.title3.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button("Close") { model.dismissImportSheet() }
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    // MARK: - Sections

    private func packageSummary(_ package: ImportPackage) -> some View {
        GroupBox {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playlist").font(.caption).foregroundStyle(.secondary)
                    Text(package.playlistName).font(.title3.weight(.semibold))
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Presentations").font(.caption).foregroundStyle(.secondary)
                    Text("\(package.presentations.count) song(s)").font(.body.weight(.medium))
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exported From").font(.caption).foregroundStyle(.secondary)
                    Text(package.manifest.source?.hostDescription ?? "ProPresenter")
                        .font(.body.weight(.medium))
                }
                Spacer()
            }
            .padding(6)
        }
    }

    private func packageView(_ package: ImportPackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                packageSummary(package)
                configurationSection(package)
                presentationsSection(package)
            }
            .padding(20)
        }
    }

    private func configurationSection(_ package: ImportPackage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            // Target Library
            VStack(alignment: .leading, spacing: 6) {
                Text("Target Library").font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { model.selectedTargetLibraryURL ?? model.availableLibraries.first },
                        set: { model.selectedTargetLibraryURL = $0 }
                    )) {
                        ForEach(model.availableLibraries, id: \.self) { url in
                            Text(url.lastPathComponent).tag(Optional(url))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    Button("Choose Folder…") {
                        let panel = NSOpenPanel()
                        panel.title = "Choose Target Library Folder"
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            model.selectedTargetLibraryURL = url
                        }
                    }
                }
                if let target = model.selectedTargetLibraryURL ?? model.availableLibraries.first {
                    Text(target.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            // Song Conflict Policy
            VStack(alignment: .leading, spacing: 6) {
                Text("If Song Already Exists in Library").font(.subheadline.weight(.medium))
                Picker("", selection: Binding(
                    get: { model.songConflictPolicy },
                    set: { model.songConflictPolicy = $0 }
                )) {
                    ForEach(SongConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.songConflictPolicy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Playlist Conflict Policy
            VStack(alignment: .leading, spacing: 6) {
                Text("If Playlist Already Exists in ProPresenter").font(.subheadline.weight(.medium))
                Picker("", selection: Binding(
                    get: { model.playlistConflictPolicy },
                    set: { model.playlistConflictPolicy = $0 }
                )) {
                    ForEach(PlaylistConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.playlistConflictPolicy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }

    private func presentationsSection(_ package: ImportPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presentations in Package (\(package.presentations.count))").font(.headline)

            VStack(spacing: 0) {
                ForEach(package.presentations) { presentation in
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.name).font(.body.weight(.medium))
                            HStack(spacing: 8) {
                                Text("\(presentation.slideCount) slides")
                                if !presentation.groupNames.isEmpty {
                                    Text("·")
                                    Text(presentation.groupNames.joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    Divider()
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
        }
    }

    private func finishedView(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Import Complete!").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Library:")
                    Spacer()
                    Text(result.targetLibraryName).bold()
                }
                HStack {
                    Text("Songs Imported:")
                    Spacer()
                    Text("\(result.importedSongsCount)").bold()
                }
                if result.renamedSongsCount > 0 {
                    HStack {
                        Text("Songs Renamed:")
                        Spacer()
                        Text("\(result.renamedSongsCount) (kept both)").bold()
                    }
                }
                if result.skippedSongsCount > 0 {
                    HStack {
                        Text("Songs Skipped:")
                        Spacer()
                        Text("\(result.skippedSongsCount) (kept existing)").bold()
                    }
                }
                if let plName = result.playlistName {
                    HStack {
                        Text("Playlist:")
                        Spacer()
                        Text(plName).bold()
                    }
                }
            }
            .frame(width: 320)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))

            Button("Done") { model.dismissImportSheet() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if case .importing(_, let progress) = model.importState {
                HStack(spacing: 8) {
                    if let frac = progress.fraction {
                        ProgressView(value: frac).frame(width: 140)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("\(progress.phase.rawValue): \(progress.message)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Cancel") { model.cancelImport() }
                .disabled(model.importState.isBusy)

            if case .ready = model.importState {
                Button("Import") { model.startImport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.bar)
    }
}
