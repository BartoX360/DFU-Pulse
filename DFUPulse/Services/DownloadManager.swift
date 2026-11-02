import Foundation
import Observation

/// Downloads IPSW files into the library. Interrupted downloads keep their
/// resume data on disk, so a 20 GB transfer survives a network drop or a quit.
@MainActor @Observable
final class DownloadManager: NSObject {
    enum Status: Equatable {
        case downloading(received: Int64, total: Int64)
        case paused
        case verifying(Double)
        case failed(String)
    }

    private(set) var statuses: [String: Status] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var firmwares: [String: Firmware] = [:]
    private let library: IPSWLibrary
    @ObservationIgnored private lazy var session = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil)

    init(library: IPSWLibrary) {
        self.library = library
    }

    func start(_ firmware: Firmware) {
        guard TrustedSource.isApple(firmware.url) else {
            statuses[firmware.build] = .failed(String(localized: "Refused: this file is not hosted by Apple."))
            return
        }
        if let size = firmware.size, let free = freeSpace(), free < size {
            statuses[firmware.build] = .failed(String(localized: "Not enough free disk space: \(size.fileSize) needed."))
            return
        }
        firmwares[firmware.build] = firmware
        let task: URLSessionDownloadTask
        if let resume = try? Data(contentsOf: resumeFile(firmware.build)) {
            task = session.downloadTask(withResumeData: resume)
        } else {
            task = session.downloadTask(with: firmware.url)
        }
        task.taskDescription = firmware.build
        tasks[firmware.build] = task
        statuses[firmware.build] = .downloading(received: 0, total: firmware.size ?? 0)
        task.resume()
    }

    func pause(_ build: String) {
        guard let task = tasks.removeValue(forKey: build) else { return }
        statuses[build] = .paused
        task.cancel { [weak self] data in
            guard let data else { return }
            Task { @MainActor in self?.storeResumeData(data, build: build) }
        }
    }

    func discard(_ build: String) {
        tasks.removeValue(forKey: build)?.cancel()
        try? FileManager.default.removeItem(at: resumeFile(build))
        statuses[build] = nil
    }

    private func resumeFile(_ build: String) -> URL {
        library.folder.appending(path: ".\(build).resume")
    }

    private func storeResumeData(_ data: Data, build: String) {
        try? data.write(to: resumeFile(build))
    }

    private func freeSpace() -> Int64? {
        let values = try? library.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func install(_ temporary: URL, build: String) async {
        guard let firmware = firmwares[build] else { return }
        statuses[build] = .verifying(0)
        do {
            let matches = try await IPSWVerifier.verify(temporary, firmware: firmware) { value in
                Task { @MainActor [weak self] in self?.updateVerification(build: build, value: value) }
            }
            guard matches != false else {
                try? FileManager.default.removeItem(at: temporary)
                statuses[build] = .failed(String(localized: "Checksum mismatch: the file was deleted."))
                return
            }
            let destination = library.folder.appending(path: firmware.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            statuses[build] = nil
            library.refresh()
        } catch {
            statuses[build] = .failed(error.localizedDescription)
        }
    }

    private func updateVerification(build: String, value: Double) {
        if case .verifying = statuses[build] { statuses[build] = .verifying(value) }
    }

    private func updateProgress(build: String, received: Int64, total: Int64) {
        if case .downloading = statuses[build] {
            statuses[build] = .downloading(received: received, total: total)
        }
    }

    private func handleFailure(build: String, error: Error) {
        tasks[build] = nil
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        if let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            storeResumeData(resume, build: build)
        }
        statuses[build] = .failed(error.localizedDescription)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let build = downloadTask.taskDescription else { return }
        Task { @MainActor in
            updateProgress(build: build, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let build = downloadTask.taskDescription else { return }
        // URLSession deletes `location` when this returns, so claim it now.
        let kept = location.deletingLastPathComponent().appending(path: "\(build).ipsw.part")
        try? FileManager.default.removeItem(at: kept)
        guard (try? FileManager.default.moveItem(at: location, to: kept)) != nil else { return }
        Task { @MainActor in
            tasks[build] = nil
            try? FileManager.default.removeItem(at: resumeFile(build))
            await install(kept, build: build)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error, let build = task.taskDescription else { return }
        Task { @MainActor in handleFailure(build: build, error: error) }
    }
}
