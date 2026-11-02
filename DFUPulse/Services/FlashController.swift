import Foundation
import Observation

/// Runs one cfgutil revive or restore and streams its output.
@MainActor @Observable
final class FlashController {
    enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(Int32)
    }

    private(set) var state: State = .idle
    private(set) var progress: Double?
    private(set) var log: [String] = []
    private var process: Process?
    private var activity: NSObjectProtocol?

    var isRunning: Bool { state == .running }

    func start(mode: RestoreMode, target: TargetDevice, ipsw: URL?) {
        guard !isRunning else { return }
        state = .running
        progress = nil
        log = []

        let process = Process()
        process.executableURL = URL(filePath: Configurator.toolPath)
        process.arguments = Configurator.arguments(mode: mode, ecid: target.ecid, ipsw: ipsw)
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // A restore lasts many minutes: the host must not sleep halfway through.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Flashing a device")

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: chunk, as: UTF8.self)
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.finish(status: status) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            log.append(error.localizedDescription)
            finish(status: -1)
        }
    }

    func cancel() {
        process?.terminate()
    }

    func reset() {
        guard !isRunning else { return }
        state = .idle
        progress = nil
        log = []
    }

    private func append(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            let line = String(line).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let value = Configurator.progress(in: line) { progress = value }
            log.append(line)
        }
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    private func finish(status: Int32) {
        state = status == 0 ? .succeeded : .failed(status)
        process = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
