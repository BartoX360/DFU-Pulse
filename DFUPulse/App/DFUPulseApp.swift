import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
    let catalog = CatalogService()
    let library: IPSWLibrary
    let downloads: DownloadManager
    let monitor = DeviceMonitor()
    let flash = FlashController()

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

    var body: some Scene {
        Window("DFU Pulse", id: "main") {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 860, minHeight: 620)
                .task { await model.monitor.watch() }
                .task { await model.catalog.loadModels() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
