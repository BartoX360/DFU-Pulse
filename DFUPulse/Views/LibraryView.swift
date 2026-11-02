import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var catalogModel = AppModel.hostModel
    @State private var showImporter = false
    @State private var pendingTrash: LibraryItem?
    @State private var verifying: URL?
    @State private var results: [URL: Bool] = [:]
    @State private var errorMessage: String?
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Library", subtitle: "The IPSW files stored on this Mac.")
                filesCard
                catalogCard
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.library.refresh() }
        .task(id: catalogModel) { await model.catalog.load(model: catalogModel) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert("Move to Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
               presenting: pendingTrash) { item in
            Button("Move to Trash", role: .destructive) { trash(item) }
        } message: { item in
            Text(verbatim: "\(item.name) (\(item.size.fileSize))")
        }
    }

    private var filesCard: some View {
        GlassCard {
            HStack {
                Text("\(model.library.items.count) files · \(model.library.totalSize.fileSize)")
                    .font(.headline)
                Spacer()
                Button("Import", systemImage: "plus") { showImporter = true }
                    .buttonStyle(.glass)
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.library.folder])
                }
                .labelStyle(.iconOnly).buttonStyle(.glass)
                Button("Change folder", systemImage: "folder.badge.gearshape") { chooseFolder() }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }
            if model.library.items.isEmpty {
                Text(dropTargeted ? "Drop to import" : "No IPSW yet. Download one below or drop files here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.library.items) { item in
                row(item)
                if item.id != model.library.items.last?.id { Divider() }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func row(_ item: LibraryItem) -> some View {
        let firmware = item.build.flatMap(model.catalog.firmware(build:))
        return HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.version.map { "macOS \($0)" } ?? item.name)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(verbatim: [item.build, item.size.fileSize].compactMap(\.self).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if firmware?.signed == false { Badge(text: "No longer signed", tint: .orange) }
            if let result = results[item.url] {
                Badge(text: result ? "Intact" : "Corrupted", tint: result ? .green : .red)
            }
            if verifying == item.url {
                ProgressView().controlSize(.small)
            } else if let firmware {
                Button("Verify", systemImage: "checkmark.shield") { verify(item, firmware) }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }
            Button("Show in Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .labelStyle(.iconOnly).buttonStyle(.glass)
            Button("Move to Trash", systemImage: "trash") { pendingTrash = item }
                .labelStyle(.iconOnly).buttonStyle(.glass)
        }
    }

    private var catalogCard: some View {
        GlassCard {
            HStack {
                Text("Download").font(.headline)
                Spacer()
                Picker("Mac model", selection: $catalogModel) {
                    ForEach(modelChoices, id: \.self) { id in
                        Text(verbatim: model.catalog.displayName(for: id)).tag(id)
                    }
                }
                .frame(maxWidth: 340)
            }
            let list = (model.catalog.firmwares[catalogModel] ?? []).filter(\.signed)
            if let failure = model.catalog.failures[catalogModel] {
                Text(failure).foregroundStyle(.orange)
            } else if list.isEmpty {
                ProgressView()
            }
            ForEach(list) { firmware in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "macOS \(firmware.version)").font(.headline)
                        Text(verbatim: [firmware.build, firmware.size?.fileSize].compactMap(\.self).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.library.item(build: firmware.build) != nil {
                        Badge(text: "In library", tint: .green)
                    } else {
                        DownloadControl(firmware: firmware)
                    }
                }
            }
        }
    }

    private var modelChoices: [String] {
        var ids = Array(model.catalog.macNames.keys)
        if !ids.contains(catalogModel) { ids.append(catalogModel) }
        return ids.sorted { model.catalog.displayName(for: $0) < model.catalog.displayName(for: $1) }
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

    private func verify(_ item: LibraryItem, _ firmware: Firmware) {
        verifying = item.url
        Task {
            defer { verifying = nil }
            do {
                results[item.url] = try await IPSWVerifier.verify(item.url, firmware: firmware) { _ in }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.library.setFolder(url)
        }
    }
}
