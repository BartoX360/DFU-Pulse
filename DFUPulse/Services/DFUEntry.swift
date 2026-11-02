import Foundation

/// Puts a connected Mac into DFU mode over USB-C with the bundled macvdmtool.
/// Needs root, so macOS asks for an administrator password.
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

    static var toolURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "macvdmtool")
    }

    static func run() async throws {
        guard let tool = toolURL else { throw Failure.missingTool }
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "do shell script (quoted form of item 1 of argv) & \" dfu 2>&1\" with administrator privileges",
                "-e", "end run",
                tool.path(percentEncoded: false),
            ]
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
