import Foundation
import Observation
import Sparkle

/// Updates from the GitHub releases, through Sparkle. Each release carries an
/// appcast.xml describing the DMG, signed with the project's EdDSA key; the
/// app checks it once a day and can install the update when it quits.
@MainActor @Observable
final class Updates {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    var automaticInstalls: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticInstalls }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    init() {
        // A development build would replace itself with the published one.
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        automaticInstalls = controller.updater.automaticallyDownloadsUpdates
    }

    func check() {
        controller.checkForUpdates(nil)
    }
}
