import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var access = DFUEntry.access
    @State private var hasLegacySetup = DFUEntry.hasLegacySetup
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    switch access {
                    case .helper: Text("No password needed")
                    case .needsApproval: Text("Waiting for approval in System Settings").foregroundStyle(.orange)
                    case .askEveryTime: Text("Asks for a password")
                    }
                }
                HStack {
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    switch access {
                    case .helper:
                        Button("Disable") { change(DFUEntry.disableHelper) }
                    case .needsApproval:
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.glassProminent)
                    case .askEveryTime:
                        Button("Enable the helper") { change { try DFUEntry.enableHelper() } }
                            .buttonStyle(.glassProminent)
                    }
                }
                .disabled(working)
                if hasLegacySetup {
                    LabeledContent {
                        Button("Remove") { change(DFUEntry.removeLegacySetup) }
                            .disabled(working)
                    } label: {
                        Text("Old sudo rule")
                        Text("Left by DFU Pulse 0.4 and earlier, no longer used.")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            } header: {
                Text("Automatic DFU entry")
            } footer: {
                Text("The helper is a small part of DFU Pulse that macOS starts with administrator rights when needed. It only answers DFU Pulse and only puts a Mac into DFU. You switch it on once in System Settings › General › Login Items & Extensions.")
                    .foregroundStyle(.secondary)
            }

            Section {
                @Bindable var updates = model.updates
                Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                Toggle("Download and install updates automatically", isOn: $updates.automaticInstalls)
                    .disabled(!updates.automaticChecks)
                LabeledContent {
                    Button("Check Now") { updates.check() }
                } label: {
                    Text("Version \(Updates.version)")
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates come from the project's GitHub releases. They are signed and notarized, and installed when DFU Pulse quits.")
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        access = DFUEntry.access
        hasLegacySetup = DFUEntry.hasLegacySetup
    }

    private func change(_ action: @escaping () async throws -> Void) {
        working = true
        errorMessage = nil
        Task {
            defer {
                working = false
                refresh()
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
