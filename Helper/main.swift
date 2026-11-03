import Darwin
import Foundation
import Security

/// DFU Pulse's privileged helper. launchd starts it on demand, as root, when
/// the app connects to its Mach service; it does one thing: `macvdmtool dfu`.
/// It quits when the app disconnects, so an updated app always gets the
/// helper from its own bundle.
final class Helper: NSObject, NSXPCListenerDelegate, DFUHelperProtocol, @unchecked Sendable {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: DFUHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { exit(0) }
        connection.resume()
        return true
    }

    func enterDFU(withReply reply: @escaping @Sendable (Int32, String) -> Void) {
        do {
            let tool = try trustedCopyOfTool()
            defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
            let process = Process()
            process.executableURL = tool
            process.arguments = ["dfu"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            reply(process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            reply(-1, error.localizedDescription)
        }
    }

    /// The app bundle may be writable by the user, so the tool next to this
    /// helper is copied somewhere only root can write, and its signature is
    /// checked on that copy, which is the one that runs.
    private func trustedCopyOfTool() throws -> URL {
        // launchd does not pass a full path in argv[0]: ask the kernel.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else {
            throw CocoaError(.fileNoSuchFile)
        }
        let bundled = URL(filePath: String(cString: path))
            .deletingLastPathComponent().appending(path: "macvdmtool")
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let copy = folder.appending(path: "macvdmtool")
        try FileManager.default.copyItem(at: bundled, to: copy)

        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(copy as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(HelperIdentity.requirement(identifier: "macvdmtool") as CFString,
                                             [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
        else {
            try? FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "macvdmtool failed its signature check."])
        }
        return copy
    }
}

let helper = Helper()
let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
listener.setConnectionCodeSigningRequirement(HelperIdentity.requirement(identifier: "fr.bartox.DFUPulse"))
listener.delegate = helper
listener.resume()
RunLoop.main.run()
