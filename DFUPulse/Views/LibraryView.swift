import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false
    @State private var pendingTrash: LibraryItem?
    @State private var verifying: URL?
    @State private var results: [URL: Bool] = [:]
    @State private var errorMessage: String?
    @State private var compatibility: Firmware?

    /// Releases grouped by major version, newest first.
    private var majors: [(String, [Firmware])] {
        var groups: [(String, [Firmware])] = []
        for release in model.catalog.releases {
            if groups.last?.0 == release.major {
                groups[groups.count - 1].1.append(release)
            } else {
                groups.append((release.major, [release]))
            }
        }
        return groups
    }

    var body: some View {
        Form {
            Section {
                if model.library.items.isEmpty {
                    Text("No IPSW yet. Download one below or drop files here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.library.items) { item in
                    row(item)
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.orange)
                }
            } header: {
                HStack {
                    Text("On this Mac")
                    Spacer()
                    Text("\(model.library.items.count) files · \(model.library.totalSize.fileSize)")
                        .foregroundStyle(.secondary)
                }
            }

            if model.catalog.releases.isEmpty {
                Section("Available from Apple") {
                    if model.catalog.isLoading {
                        ProgressView()
                    } else {
                        Text(model.catalog.failure ?? "")
                        Button("Retry") { Task { await model.catalog.refresh() } }
                    }
                }
            }
            ForEach(Array(majors.enumerated()), id: \.element.0) { index, group in
                Section {
                    ForEach(group.1) { release in
                        releaseRow(release)
                    }
                } header: {
                    if index == 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available from Apple")
                            Text("One file per version, shared by every Apple silicon Mac it supports.")
                                .font(.callout).fontWeight(.regular).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 6)
                    }
                    Text(verbatim: "macOS \(group.0)")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItemGroup {
                Button("Import", systemImage: "plus") { showImporter = true }
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.library.folder])
                }
            }
        }
        .sheet(item: $compatibility) { release in
            CompatibilityView(release: release)
        }
        .onAppear { model.library.refresh() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        }
        .alert("Move to Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
               presenting: pendingTrash) { item in
            Button("Move to Trash", role: .destructive) { trash(item) }
        } message: { item in
            Text(verbatim: "\(item.name) (\(item.size.fileSize))")
        }
    }

    private func row(_ item: LibraryItem) -> some View {
        let release = item.build.flatMap(model.catalog.firmware(build:))
        return LabeledContent {
            HStack(spacing: 10) {
                if let result = results[item.url] {
                    Text(result ? "Intact" : "Corrupted")
                        .font(.callout).foregroundStyle(result ? .green : .red)
                }
                if verifying == item.url {
                    ProgressView().controlSize(.small)
                }
                Menu("Actions", systemImage: "ellipsis.circle") {
                    if let release {
                        Button("Verify", systemImage: "checkmark.shield") { verify(item, release) }
                    }
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Divider()
                    Button("Move to Trash", systemImage: "trash", role: .destructive) { pendingTrash = item }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.button).buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } label: {
            Text(verbatim: item.version.map { "macOS \($0)" } ?? item.name)
            Text(verbatim: [item.build, item.size.fileSize].compactMap(\.self).joined(separator: " · ")
                 + (release == nil && item.build != nil && !model.catalog.releases.isEmpty
                    ? " · " + String(localized: "no longer signed by Apple") : ""))
        }
    }

    private func releaseRow(_ release: Firmware) -> some View {
        LabeledContent {
            if model.library.item(build: release.build) != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("In library")
            } else {
                DownloadControl(firmware: release)
            }
        } label: {
            Text(verbatim: "macOS \(release.version)")
            HStack(spacing: 4) {
                Text(verbatim: [release.build, release.size?.fileSize].compactMap(\.self).joined(separator: " · ") + " ·")
                Button("\(release.models.count) Mac models") { compatibility = release }
                    .buttonStyle(.link)
                    .help("Show compatible Macs")
            }
        }
    }

    private func add(_ urls: [URL]) {
        Task {
            do {
                try await model.library.importFiles(urls)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func trash(_ item: LibraryItem) {
        do {
            try model.library.trash(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify(_ item: LibraryItem, _ release: Firmware) {
        verifying = item.url
        Task {
            defer { verifying = nil }
            do {
                results[item.url] = try await IPSWVerifier.verify(item.url, firmware: release) { _ in }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
