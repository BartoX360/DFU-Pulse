import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var access = DFUEntry.access
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    switch access {
                    case .passwordless: Text("No password needed")
                    case .outdated: Text("Needs an update").foregroundStyle(.orange)
                    case .askEveryTime: Text("Asks for a password")
                    }
                }
                HStack {
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if access != .askEveryTime {
                        Button("Remove") { change(DFUEntry.removePasswordless) }
                    }
                    if access != .passwordless {
                        Button(access == .outdated ? "Update" : "Allow without password") {
                            change(DFUEntry.installPasswordless)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .disabled(working)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            } header: {
                Text("Automatic DFU entry")
            } footer: {
                Text("Asks for your administrator password once, then installs a copy of macvdmtool owned by root and a sudo rule that lets your account run only “macvdmtool dfu” without a password. Nothing runs in the background.")
                    .foregroundStyle(.secondary)
            }

            Section("IPSW folder") {
                LabeledContent {
                    Button("Change…") { chooseFolder() }
                } label: {
                    Text(verbatim: model.library.folder.path(percentEncoded: false))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func change(_ action: @escaping () async throws -> Void) {
        working = true
        errorMessage = nil
        Task {
            defer {
                working = false
                access = DFUEntry.access
            }
            do {
                try await action()
            } catch DFUEntry.Failure.cancelled {
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
