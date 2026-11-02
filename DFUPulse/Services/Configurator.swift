import Foundation
import Observation

/// Thin layer over `cfgutil`, the command-line tool inside Apple Configurator
/// that performs the actual revive and restore.
enum Configurator {
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/apple-configurator/id1037126344")!

    static var toolPath: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["DFUPULSE_CFGUTIL"] { return override }
        #endif
        return "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil"
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: toolPath)
    }

    static func listDevices() async -> [TargetDevice] {
        let tool = toolPath
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = ["--format", "JSON", "list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseDevices(data)
        }.value
    }

    /// `cfgutil --format JSON list` keys devices by ECID under "Output".
    static func parseDevices(_ data: Data) -> [TargetDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["Output"] as? [String: Any] else { return [] }
        return output.compactMap { key, value -> TargetDevice? in
            guard let info = value as? [String: Any],
                  let model = info["deviceType"] as? String,
                  model.hasPrefix("Mac") || model.hasPrefix("iBridge") else { return nil }
            return TargetDevice(ecid: (info["ECID"] as? String) ?? key, model: model,
                                name: info["name"] as? String,
                                location: (info["locationID"] as? NSNumber)?.stringValue)
        }
        .sorted { $0.ecid < $1.ecid }
    }

    static func arguments(mode: RestoreMode, ecid: String, ipsw: URL?) -> [String] {
        var arguments = ["--progress", "-e", ecid, mode.rawValue]
        if mode == .restore, let ipsw {
            arguments += ["-I", ipsw.path(percentEncoded: false)]
        }
        return arguments
    }

    /// Finds the last percentage in a line of cfgutil output.
    static func progress(in line: String) -> Double? {
        guard let match = line.matches(of: /(\d{1,3}(?:\.\d+)?)\s*%/).last,
              let value = Double(match.1), value <= 100 else { return nil }
        return value / 100
    }
}

/// Watches for Macs connected in DFU mode.
@MainActor @Observable
final class DeviceMonitor {
    private(set) var devices: [TargetDevice] = []
    private(set) var hasScanned = false
    var isPaused = false

    func watch() async {
        while !Task.isCancelled {
            if !isPaused {
                devices = await Configurator.listDevices()
                hasScanned = true
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
