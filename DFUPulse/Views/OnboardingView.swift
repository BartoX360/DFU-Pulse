import AppKit
import ServiceManagement
import SwiftUI

/// Shown on first launch, and from Help → Welcome to DFU Pulse.
/// Walks through what the app does and the two one-time setup steps.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var configuratorInstalled = Configurator.isInstalled
    @State private var access = DFUEntry.access
    @State private var errorMessage: String?

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: configurator
                case 2: password
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 40)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.accentColor : .secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                if page < pageCount - 1 {
                    Button(page == 2 && access != .helper ? "Later" : "Continue") { page += 1 }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 460)
        .animation(.smooth, value: page)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            configuratorInstalled = Configurator.isInstalled
            access = DFUEntry.access
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image("Logo").resizable().frame(width: 96, height: 96)
            Text("Welcome to DFU Pulse").font(.largeTitle.bold())
            Text("Revive or restore a Mac, iPhone or iPad that no longer starts, from this Mac, over a cable.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                feature("bolt", "Flash", "Revive keeps a Mac's data. Restore erases the device and installs the version you choose.")
                feature("externaldrive", "Library", "Downloads Apple's restore images once and keeps them on this Mac.")
                feature("cable.connector", "Port guide", "Shows which port to use on each Mac, and the buttons for iPhone and iPad.")
            }
            .padding(.top, 8)
        }
    }

    private var configurator: some View {
        step(symbol: "wrench.and.screwdriver", title: "Install Apple Configurator",
             text: "DFU Pulse uses Apple's free Apple Configurator to install the system on the other device. It must be in your Applications folder.") {
            if configuratorInstalled {
                Label("Apple Configurator is installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Link("Get it on the Mac App Store", destination: Configurator.appStoreURL)
                    .buttonStyle(.glass)
                Text("Come back here once it is installed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var password: some View {
        step(symbol: "lock.open", title: "Enter DFU without a password",
             text: "To put the other Mac into DFU for you, DFU Pulse needs administrator rights. Switch its helper on once, and no password will be asked again for this.") {
            Text("macOS lists the helper in System Settings › General › Login Items & Extensions. It only answers DFU Pulse, only puts a Mac into DFU, and you can switch it off there or in Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch access {
            case .helper:
                Label("Done: no password will be asked.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .needsApproval:
                Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.glass)
                Text("Turn on DFU Pulse under “Allow in the Background”, then come back here.")
                    .font(.callout).foregroundStyle(.secondary)
            case .askEveryTime:
                Button("Enable the helper") { enable() }
                    .buttonStyle(.glass)
                Text("You can also skip this: macOS will then ask for the password each time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private var ready: some View {
        step(symbol: "checkmark.seal", title: "You're ready",
             text: "Connect the device to flash with a cable that carries data, on its DFU port for a Mac. The Port guide shows which one.") {
            Text("Then use “Enter DFU automatically” for a Mac, or the button sequence from the guide. The device shows up in Flash as soon as it is in DFU mode.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step<Content: View>(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tint)
            Text(title).font(.title.bold())
            Text(text).fixedSize(horizontal: false, vertical: true)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func enable() {
        errorMessage = nil
        do {
            try DFUEntry.enableHelper()
        } catch {
            errorMessage = error.localizedDescription
        }
        access = DFUEntry.access
    }
}
