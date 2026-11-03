import Foundation
import ServiceManagement

/// Puts a connected Mac into DFU mode over USB-C with the bundled macvdmtool,
/// which needs root.
///
/// Without setup, macOS asks for an administrator password every time. The
/// user can instead enable, once, a helper that launchd runs as root on
/// demand (SMAppService). The helper only accepts DFU Pulse, signed by the
/// same team, and only runs `macvdmtool dfu`.
enum DFUEntry {
    enum Failure: LocalizedError {
        case missingTool
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingTool: String(localized: "macvdmtool is missing from the app.")
            case .cancelled: String(localized: "Cancelled.")
            case .failed(let output): output
            }
        }
    }

    enum Access: Equatable {
        case askEveryTime
        /// Registered, waiting for the switch in System Settings.
        case needsApproval
        case helper
    }

    /// Left by versions up to 0.4: a root copy of macvdmtool and a sudo rule.
    static let legacyTool = "/usr/local/libexec/dfupulse/macvdmtool"
    static let legacySudoers = "/etc/sudoers.d/dfupulse"

    static var hasLegacySetup: Bool {
        FileManager.default.fileExists(atPath: legacyTool)
    }

    private static var service: SMAppService {
        .daemon(plistName: HelperIdentity.plistName)
    }

    static var bundledTool: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "macvdmtool")
    }

    static var access: Access {
        switch service.status {
        case .enabled: .helper
        case .requiresApproval: .needsApproval
        default: .askEveryTime
        }
    }

    static func run() async throws {
        if access == .helper {
            try await callHelper()
        } else {
            guard let tool = bundledTool else { throw Failure.missingTool }
            try await asAdministrator("quoted form of item 1 of argv & \" dfu\"", [tool.path(percentEncoded: false)])
        }
    }

    /// Registers the helper. macOS then lists it in Login Items & Extensions,
    /// where the user switches it on once.
    static func enableHelper() throws {
        do {
            try service.register()
        } catch {
            // Already registered but not yet approved: just show the switch.
            guard service.status == .requiresApproval else { throw Failure.failed(error.localizedDescription) }
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    static func disableHelper() async throws {
        try await service.unregister()
    }

    static func removeLegacySetup() async throws {
        let directory = (legacyTool as NSString).deletingLastPathComponent
        try await asAdministrator("\"rm -f \" & quoted form of item 1 of argv & \"; rm -rf \" & quoted form of item 2 of argv",
                                  [legacySudoers, directory])
    }

    private static func callHelper() async throws {
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DFUHelperProtocol.self)
        connection.setCodeSigningRequirement(HelperIdentity.requirement(identifier: "DFUPulseHelper"))
        connection.resume()
        defer { connection.invalidate() }
        let (status, output) = try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { once.resume(throwing: $0) }
            guard let helper = proxy as? DFUHelperProtocol else {
                once.resume(throwing: Failure.failed(String(localized: "The helper did not answer.")))
                return
            }
            helper.enterDFU { status, output in once.resume(returning: (status, output)) }
        }
        guard status == 0 else {
            throw Failure.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// XPC may call both the reply and the error handler; resume only once.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<(Int32, String), Error>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<(Int32, String), Error>) {
            self.continuation = continuation
        }

        private func take() -> CheckedContinuation<(Int32, String), Error>? {
            lock.withLock {
                defer { continuation = nil }
                return continuation
            }
        }

        func resume(returning value: (Int32, String)) { take()?.resume(returning: value) }
        func resume(throwing error: Error) { take()?.resume(throwing: error) }
    }

    /// Runs a shell command built in AppleScript from `argv`, so paths and
    /// values are always passed through `quoted form` rather than spliced in.
    private static func asAdministrator(_ command: String, _ arguments: [String]) async throws {
        try await execute("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "do shell script (\(command)) & \" 2>&1\" with administrator privileges",
            "-e", "end run",
        ] + arguments)
    }

    private static func execute(_ executable: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw output.contains("-128") ? Failure.cancelled : Failure.failed(output)
            }
        }.value
    }
}
