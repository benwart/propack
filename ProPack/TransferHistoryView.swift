import AppKit
import SwiftUI

// MARK: - History UI View

@MainActor
struct TransferHistoryView: View {
    @ObservedObject var store: TransferHistoryStore = .shared
    @Environment(\.dismiss) private var dismiss

    private var filterTypeState = State<TransferType?>(initialValue: nil)
    private var searchTextState = State<String>(initialValue: "")
    private var showingClearConfirmationState = State<Bool>(initialValue: false)

    private var filterType: TransferType? { filterTypeState.wrappedValue }
    private var searchText: String { searchTextState.wrappedValue }

    private var filteredRecords: [TransferRecord] {
        store.records.filter { record in
            if let filter = filterType, record.type != filter {
                return false
            }
            if !searchText.isEmpty {
                let lower = searchText.lowercased()
                let matchesName = record.playlistName.lowercased().contains(lower)
                let matchesDetail = record.detail.lowercased().contains(lower)
                let matchesPath = record.filePath?.lowercased().contains(lower) ?? false
                return matchesName || matchesDetail || matchesPath
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transfer History & Audit Log")
                        .font(.title2.bold())
                    Text("\(store.records.count) past package transfer(s)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !store.records.isEmpty {
                    Button(role: .destructive) {
                        showingClearConfirmationState.wrappedValue = true
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                    }
                    .confirmationDialog("Clear Transfer History?", isPresented: showingClearConfirmationState.projectedValue) {
                        Button("Clear All History", role: .destructive) {
                            store.clear()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently remove all transfer history records from this computer.")
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Filters & Search
            HStack(spacing: 12) {
                Picker("Filter", selection: filterTypeState.projectedValue) {
                    Text("All Transfers").tag(TransferType?.none)
                    ForEach(TransferType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(TransferType?.some(type))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search history…", text: searchTextState.projectedValue)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchTextState.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Records List
            if store.records.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Transfer History")
                        .font(.title3.bold())
                    Text("Exported and imported packages will appear here for reference and auditing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No matching records found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRecords) { record in
                        TransferRecordRow(record: record)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

@MainActor
private struct TransferRecordRow: View {
    let record: TransferRecord

    private var badgeColor: Color {
        switch record.type {
        case .export: .blue
        case .airdrop: .purple
        case .import: .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Type badge icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(badgeColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: record.type.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(badgeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.playlistName)
                        .font(.headline)

                    Text(record.type.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.2))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())

                    Spacer()

                    Text(record.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !record.detail.isEmpty {
                    Text(record.detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 12) {
                    Label("\(record.presentationCount) presentation(s)", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if record.mediaCount > 0 {
                        Label("\(record.mediaCount) media file(s)", systemImage: "photo.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let size = record.formattedFileSize {
                        Label(size, systemImage: "externaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let path = record.filePath, record.fileExistsOnDisk {
                        Button {
                            let url = URL(fileURLWithPath: path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }
}
