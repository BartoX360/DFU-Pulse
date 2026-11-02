import CryptoKit
import Foundation

/// Puts a connected Mac into DFU mode over USB-C with the bundled macvdmtool,
/// which needs root.
///
/// By default macOS asks for an administrator password every time. The user
/// can instead install, once, a root-owned copy of the tool and a sudoers rule
/// that allows exactly `macvdmtool dfu` for their account, and nothing else.
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
        case passwordless
        /// Installed from an older version of the app.
        case outdated
    }

    static let installedTool = "/usr/local/libexec/dfupulse/macvdmtool"
    static let sudoersFile = "/etc/sudoers.d/dfupulse"

    static var bundledTool: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "macvdmtool")
    }

    static var access: Access {
        let files = FileManager.default
        // sudoers.d is unreadable without root: its presence is enough.
        guard files.fileExists(atPath: installedTool), files.fileExists(atPath: sudoersFile) else {
            return .askEveryTime
        }
        guard let bundled = bundledTool, digest(of: bundled) == digest(of: URL(filePath: installedTool)) else {
            return .outdated
        }
        return .passwordless
    }

    static func run() async throws {
        if access == .passwordless {
            try await execute("/usr/bin/sudo", ["-n", installedTool, "dfu"])
        } else {
            guard let tool = bundledTool else { throw Failure.missingTool }
            try await asAdministrator("quoted form of item 1 of argv & \" dfu\"", [tool.path(percentEncoded: false)])
        }
    }

    static func installPasswordless() async throws {
        guard let tool = bundledTool else { throw Failure.missingTool }
        let user = NSUserName()
        // The name goes into a sudoers rule: refuse anything unusual.
        guard user.wholeMatch(of: /[A-Za-z0-9._-]+/) != nil else {
            throw Failure.failed(String(localized: "Unsupported account name."))
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(installedTool) dfu\n"
        let directory = (installedTool as NSString).deletingLastPathComponent
        // AppleScript pieces; the rule is checked by visudo before it goes live.
        let script = [
            #""set -e; d=$(mktemp -d); trap 'rm -rf \"$d\"' EXIT; mkdir -p ""#,
            "quoted form of item 3 of argv",
            #""; install -o root -g wheel -m 755 ""#,
            "quoted form of item 1 of argv", #"" ""#, "quoted form of item 4 of argv",
            #""; printf %s ""#, "quoted form of item 2 of argv",
            #"" > \"$d/rule\"; visudo -cf \"$d/rule\" >/dev/null; install -o root -g wheel -m 440 \"$d/rule\" ""#,
            "quoted form of item 5 of argv",
        ].joined(separator: " & ")
        try await asAdministrator(script, [tool.path(percentEncoded: false), rule, directory, installedTool, sudoersFile])
    }

    static func removePasswordless() async throws {
        let directory = (installedTool as NSString).deletingLastPathComponent
        try await asAdministrator("\"rm -f \" & quoted form of item 1 of argv & \"; rm -rf \" & quoted form of item 2 of argv",
                                  [sudoersFile, directory])
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

    private static func digest(of url: URL) -> SHA256.Digest? {
        (try? Data(contentsOf: url)).map(SHA256.hash(data:))
    }
}
