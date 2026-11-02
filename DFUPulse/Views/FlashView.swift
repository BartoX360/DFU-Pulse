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

    private var signed: [Firmware] {
        guard let target else { return [] }
        return (model.catalog.firmwares[target.model] ?? []).filter(\.signed)
    }

    private var selected: Firmware? {
        signed.first { $0.build == build } ?? signed.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Flash a Mac", subtitle: "Revive or restore a Mac connected in DFU mode.")
                if !Configurator.isInstalled {
                    configuratorCard
                }
                if model.flash.state == .idle {
                    targetCard
                    if let target {
                        actionCard(target)
                    }
                } else {
                    progressCard
                }
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task(id: target?.model) {
            if let target, !target.isT2 { await model.catalog.load(model: target.model) }
        }
        .onChange(of: model.flash.isRunning) { _, running in
            model.monitor.isPaused = running
        }
    }

    private var configuratorCard: some View {
        GlassCard {
            Label("Apple Configurator is required", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.yellow)
            Text("DFU Pulse relies on Apple's free tool to talk to the Mac being flashed.")
                .foregroundStyle(.secondary)
            Link("Get it on the Mac App Store", destination: Configurator.appStoreURL)
                .buttonStyle(.glass)
        }
    }

    private var targetCard: some View {
        GlassCard {
            if model.monitor.devices.isEmpty {
                AnimatedPulse().frame(height: 56)
                Text("Waiting for a Mac in DFU mode").font(.headline)
                Text("Connect the two Macs with a USB-C cable that carries data, then put the other Mac into DFU.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        Task { await enterDFU() }
                    } label: {
                        if entering {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Enter DFU automatically", systemImage: "bolt.horizontal.fill")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.cyan)
                    .disabled(entering)

                    Button("Open the port guide", systemImage: "cable.connector", action: showGuide)
                        .buttonStyle(.glass)
                }
                Text("Automatic entry needs both Macs on Apple silicon, joined by their DFU ports, and an administrator password.")
                    .font(.caption).foregroundStyle(.secondary)
                if let entryError {
                    Text(entryError).font(.caption).foregroundStyle(.orange)
                }
            } else {
                ForEach(model.monitor.devices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private func deviceRow(_ device: TargetDevice) -> some View {
        Button {
            targetID = device.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "laptopcomputer")
                    .font(.title).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.catalog.displayName(for: device.model)).font(.headline)
                    Text(verbatim: "\(device.model) · ECID \(device.ecid)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if device.id == target?.id { Badge(text: "Connected", tint: .green) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func actionCard(_ target: TargetDevice) -> some View {
        GlassCard {
            Picker("Action", selection: $mode) {
                Text("Revive").tag(RestoreMode.revive)
                Text("Restore").tag(RestoreMode.restore)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .revive:
                Text("Updates the firmware and recoveryOS and keeps the Mac's data. Try this first.")
                    .foregroundStyle(.secondary)
                Button("Revive this Mac", systemImage: "waveform.path.ecg") {
                    model.flash.start(mode: .revive, target: target, ipsw: nil)
                }
                .buttonStyle(.glassProminent).tint(.cyan)
                .disabled(!Configurator.isInstalled)
            case .restore:
                Label("Restoring erases everything on this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if target.isT2 {
                    Text("T2 Macs take no macOS image here: Apple's tool picks the firmware, then macOS installs from Recovery.")
                        .foregroundStyle(.secondary)
                    eraseButton(target, ipsw: nil)
                } else {
                    versionSection(target)
                }
            }
        }
    }

    @ViewBuilder
    private func versionSection(_ target: TargetDevice) -> some View {
        if let failure = model.catalog.failures[target.model] {
            Text(failure).foregroundStyle(.orange)
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await model.catalog.load(model: target.model) }
            }
            .buttonStyle(.glass)
        } else if let firmware = selected {
            Picker("macOS version", selection: Binding(get: { firmware.build }, set: { build = $0 })) {
                ForEach(signed) { item in
                    Text(verbatim: "macOS \(item.version) (\(item.build))" + (model.library.item(build: item.build) == nil ? "" : "  ✓"))
                        .tag(item.build)
                }
            }
            if let local = model.library.item(build: firmware.build) {
                eraseButton(target, ipsw: local.url)
            } else {
                HStack {
                    if let size = firmware.size {
                        Text(verbatim: size.fileSize).foregroundStyle(.secondary)
                    }
                    Spacer()
                    DownloadControl(firmware: firmware)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func eraseButton(_ target: TargetDevice, ipsw: URL?) -> some View {
        Button("Erase and restore", systemImage: "bolt.fill", role: .destructive) {
            confirming = true
        }
        .buttonStyle(.glassProminent).tint(.red)
        .disabled(!Configurator.isInstalled)
        .confirmationDialog("Erase this Mac?", isPresented: $confirming) {
            Button("Erase and restore", role: .destructive) {
                model.flash.start(mode: .restore, target: target, ipsw: ipsw)
            }
        } message: {
            Text("All data on \(model.catalog.displayName(for: target.model)) will be permanently deleted.")
        }
    }

    private var progressCard: some View {
        GlassCard {
            switch model.flash.state {
            case .running:
                AnimatedPulse().frame(height: 56)
                Text("Flashing in progress").font(.headline)
                Text("Keep both Macs powered and connected.").foregroundStyle(.secondary)
                if let progress = model.flash.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            case .succeeded:
                Label("Done. The Mac will restart on its own.", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
            case .failed(let status):
                Label("Flashing failed (code \(status)).", systemImage: "xmark.octagon.fill")
                    .font(.headline).foregroundStyle(.red)
            case .idle:
                EmptyView()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.flash.log.enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line).id(index)
                        }
                    }
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                .onChange(of: model.flash.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }

            if model.flash.isRunning {
                Button("Stop", systemImage: "stop.fill") { confirmingCancel = true }
                    .buttonStyle(.glass)
                    .confirmationDialog("Stop flashing?", isPresented: $confirmingCancel) {
                        Button("Stop", role: .destructive) { model.flash.cancel() }
                    } message: {
                        Text("The Mac may stay unusable until you flash it again.")
                    }
            } else {
                Button("Back") { model.flash.reset() }
                    .buttonStyle(.glass)
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
