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
                  DeviceKind(prefixOf: model) != nil else { return nil }
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

    /// cfgutil prints each progress step twice: as a property list dump
    /// ("Step = \"\\U00c9tape…\";") and as a readable line. Keeps the readable
    /// one, without the braces glued to it.
    static func logLine(_ raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        while let first = line.first, "{}".contains(first) { line.removeFirst() }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.wholeMatch(of: /(Progress|Step|Type) = .*;/) != nil { return nil }
        return line.replacing(/\\U([0-9a-fA-F]{4})/) { match in
            UInt32(match.1, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
        }
    }

    /// Room left on the volume where cfgutil unpacks the image before
    /// installing it. The smaller of the two figures: purgeable space only
    /// counts if macOS frees it, and cfgutil does not ask it to.
    static var freeSpaceForRestore: Int64? {
        let values = try? URL.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let figures = [values?.volumeAvailableCapacity.map(Int64.init), values?.volumeAvailableCapacityForImportantUsage]
        return figures.compactMap(\.self).min()
    }

    /// cfgutil unpacks the whole image, plus some working room.
    static func spaceNeeded(for ipsw: URL) -> Int64? {
        let size = try? ipsw.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size.map { Int64($0) + (2 << 30) }
    }

    /// How much is missing to restore with this image, or nil when it fits.
    static func missingSpace(for ipsw: URL) -> Int64? {
        guard let needed = spaceNeeded(for: ipsw), let free = freeSpaceForRestore, free < needed else { return nil }
        return needed - free
    }

    /// Finds the last percentage in a line of cfgutil output.
    static func progress(in line: String) -> Double? {
        guard let match = line.matches(of: /(\d{1,3}(?:\.\d+)?)\s*%/).last,
              let value = Double(match.1), value <= 100 else { return nil }
        return value / 100
    }
}

/// Watches for Macs, iPhones and iPads connected in DFU or recovery mode.
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
