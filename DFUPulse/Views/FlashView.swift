import SwiftUI

struct FlashView: View {
    @Environment(AppModel.self) private var model
    let showGuide: () -> Void

    @State private var targetID: String?
    @State private var mode: RestoreMode = .revive
    @State private var build: String?
    @State private var entering = false
    @State private var entryError: String?
    @State private var confirming = false
    @State private var confirmingCancel = false

    private var target: TargetDevice? {
        model.monitor.devices.first { $0.id == targetID } ?? model.monitor.devices.first
    }

    var body: some View {
        Form {
            if !Configurator.isInstalled {
                Section {
                    Label("Apple Configurator is required", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("DFU Pulse relies on Apple's free tool to talk to the device being flashed.")
                        .foregroundStyle(.secondary)
                    Link("Get it on the Mac App Store", destination: Configurator.appStoreURL)
                }
            }
            if model.flash.state == .idle {
                targetSection
                if let target { actionSection(target) }
            } else {
                progressSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Flash")
        .onChange(of: model.flash.isRunning) { _, running in
            model.monitor.isPaused = running
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        Section {
            if model.monitor.devices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for a device in DFU mode").font(.headline)
                    }
                    Text("Connect the Mac, iPhone or iPad with a cable that carries data, then put it into DFU. The Port guide shows how.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                HStack {
                    Button {
                        Task { await enterDFU() }
                    } label: {
                        if entering {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Enter DFU automatically")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(entering)
                    Button("Port guide", action: showGuide)
                        .buttonStyle(.glass)
                    Spacer()
                }
                if let entryError {
                    Text(entryError).font(.callout).foregroundStyle(.orange)
                }
            } else {
                Picker("Device", selection: Binding(get: { target?.id }, set: { targetID = $0 })) {
                    ForEach(model.monitor.devices) { device in
                        Text(verbatim: "\(model.catalog.displayName(for: device.model)) · \(device.ecid)")
                            .tag(Optional(device.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } header: {
            Text("Device to flash")
        } footer: {
            if model.monitor.devices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DFUEntry.access == .helper
                         ? "Automatic entry needs both Macs on Apple silicon, joined by their DFU ports."
                         : "Automatic entry needs both Macs on Apple silicon, joined by their DFU ports, and an administrator password. You can skip the password in Settings.")
                    Text("iPhones and iPads enter DFU with their buttons only.")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ target: TargetDevice) -> some View {
        if target.isMobile {
            Section {
                Text("Restoring erases everything on this device and installs the version you choose.")
                    .foregroundStyle(.orange)
                versionRows(target)
            }
            .task(id: target.model) { await model.catalog.loadReleases(for: target.model) }
        } else {
            macActionSection(target)
        }
    }

    @ViewBuilder
    private func macActionSection(_ target: TargetDevice) -> some View {
        Section {
            Picker("Action", selection: $mode) {
                Text("Revive").tag(RestoreMode.revive)
                Text("Restore").tag(RestoreMode.restore)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .revive:
                Text("Updates the firmware and recoveryOS and keeps the Mac's data. Try this first.")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Revive") { model.flash.start(mode: .revive, target: target, ipsw: nil) }
                        .buttonStyle(.glassProminent)
                        .disabled(!Configurator.isInstalled)
                }
            case .restore:
                Text("Restoring erases everything on this Mac.").foregroundStyle(.orange)
                if target.isT2 {
                    Text("T2 Macs take no macOS image here: Apple's tool picks the firmware, then macOS installs from Recovery.")
                        .foregroundStyle(.secondary)
                    restoreButton(target, ipsw: nil)
                } else {
                    versionRows(target)
                }
            }
        }
    }

    @ViewBuilder
    private func versionRows(_ target: TargetDevice) -> some View {
        let compatible = model.catalog.releases(for: target.model)
        if let firmware = compatible.first(where: { $0.build == build }) ?? compatible.first {
            Picker("Version", selection: Binding(get: { firmware.build }, set: { build = $0 })) {
                ForEach(compatible) { item in
                    Text(verbatim: "\(item.system) \(item.version) (\(item.build))"
                         + (model.library.item(for: item) == nil ? "" : "  ✓"))
                        .tag(item.build)
                }
            }
            if let local = model.library.item(for: firmware) {
                // cfgutil unpacks the whole image first, plus some working room.
                let needed = local.size + (2 << 30)
                let free = Configurator.freeSpaceForRestore
                let tooFull = free.map { $0 < needed } ?? false
                if let free, tooFull {
                    Label("Not enough free space: Apple Configurator unpacks the image before installing it. Free up \((needed - free).fileSize) on this Mac.",
                          systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                restoreButton(target, ipsw: local.url, blocked: tooFull)
            } else {
                LabeledContent {
                    DownloadControl(firmware: firmware)
                } label: {
                    Text("Not downloaded yet")
                    if let size = firmware.size { Text(verbatim: size.fileSize) }
                }
            }
        } else if model.catalog.isLoading || model.catalog.loadingModels.contains(target.model) {
            ProgressView()
        } else {
            Text(model.catalog.failure ?? String(localized: "No compatible version found."))
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.catalog.refresh() } }
        }
    }

    private func restoreButton(_ target: TargetDevice, ipsw: URL?, blocked: Bool = false) -> some View {
        HStack {
            Spacer()
            Button("Erase and restore", role: .destructive) { confirming = true }
                .buttonStyle(.glassProminent).tint(.red)
                .disabled(!Configurator.isInstalled || blocked)
        }
        .confirmationDialog("Erase this device?", isPresented: $confirming) {
            Button("Erase and restore", role: .destructive) {
                model.flash.start(mode: .restore, target: target, ipsw: ipsw)
            }
        } message: {
            Text("All data on \(model.catalog.displayName(for: target.model)) will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Section {
            switch model.flash.state {
            case .running:
                Text("Flashing in progress").font(.headline)
                Text("Keep both devices powered and connected.").foregroundStyle(.secondary)
                if let progress = model.flash.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            case .succeeded:
                Label("Done. The device will restart on its own.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .failed(let status):
                Label("Flashing failed (code \(status)).", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case .idle:
                EmptyView()
            }
            HStack {
                Spacer()
                if model.flash.isRunning {
                    Button("Stop") { confirmingCancel = true }
                        .confirmationDialog("Stop flashing?", isPresented: $confirmingCancel) {
                            Button("Stop", role: .destructive) { model.flash.cancel() }
                        } message: {
                            Text("The device may stay unusable until you flash it again.")
                        }
                } else {
                    Button("Done") { model.flash.reset() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        Section("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.flash.log.enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line).id(index)
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .onChange(of: model.flash.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func enterDFU() async {
        entering = true
        entryError = nil
        defer { entering = false }
        do {
            try await DFUEntry.run()
        } catch DFUEntry.Failure.cancelled {
        } catch {
            entryError = error.localizedDescription
        }
    }
}
