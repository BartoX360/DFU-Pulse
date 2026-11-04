import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
    let catalog = CatalogService()
    let library: IPSWLibrary
    let downloads: DownloadManager
    let monitor = DeviceMonitor()
    let flash = FlashController()
    let updates = Updates()

    init() {
        let library = IPSWLibrary()
        self.library = library
        downloads = DownloadManager(library: library)
    }

    /// The model identifier of the Mac running the app.
    static let hostModel: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()
}

@main
struct DFUPulseApp: App {
    @State private var model = AppModel()
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some Scene {
        Window("DFU Pulse", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 540)
                .task { await model.monitor.watch() }
                .task { await model.catalog.refresh() }
                .sheet(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) {
                    OnboardingView()
                        .interactiveDismissDisabled()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.updates.check() }
            }
            CommandGroup(before: .help) {
                Button("Welcome to DFU Pulse") { onboardingDone = false }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
