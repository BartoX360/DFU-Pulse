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
            statuses[firmware.id] = .failed(String(localized: "Refused: this file is not hosted by Apple."))
            return
        }
        if let size = firmware.size, let free = freeSpace(), free < size {
            statuses[firmware.id] = .failed(String(localized: "Not enough free disk space: \(size.fileSize) needed."))
            return
        }
        firmwares[firmware.id] = firmware
        let task: URLSessionDownloadTask
        if let resume = try? Data(contentsOf: resumeFile(firmware.id)) {
            task = session.downloadTask(withResumeData: resume)
        } else {
            task = session.downloadTask(with: firmware.url)
        }
        task.taskDescription = firmware.id
        tasks[firmware.id] = task
        statuses[firmware.id] = .downloading(received: 0, total: firmware.size ?? 0)
        task.resume()
    }

    func pause(_ id: String) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        statuses[id] = .paused
        task.cancel { [weak self] data in
            guard let data else { return }
            Task { @MainActor in self?.storeResumeData(data, id: id) }
        }
    }

    func discard(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        try? FileManager.default.removeItem(at: resumeFile(id))
        statuses[id] = nil
    }

    private func resumeFile(_ id: String) -> URL {
        library.folder.appending(path: ".\(id).resume")
    }

    private func storeResumeData(_ data: Data, id: String) {
        try? data.write(to: resumeFile(id))
    }

    private func freeSpace() -> Int64? {
        let values = try? library.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func install(_ temporary: URL, id: String) async {
        guard let firmware = firmwares[id] else { return }
        statuses[id] = .verifying(0)
        do {
            let matches = try await IPSWVerifier.verify(temporary, firmware: firmware) { value in
                Task { @MainActor [weak self] in self?.updateVerification(id: id, value: value) }
            }
            guard matches != false else {
                try? FileManager.default.removeItem(at: temporary)
                statuses[id] = .failed(String(localized: "Checksum mismatch: the file was deleted."))
                return
            }
            let destination = library.folder.appending(path: firmware.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            statuses[id] = nil
            library.refresh()
        } catch {
            statuses[id] = .failed(error.localizedDescription)
        }
    }

    private func updateVerification(id: String, value: Double) {
        if case .verifying = statuses[id] { statuses[id] = .verifying(value) }
    }

    private func updateProgress(id: String, received: Int64, total: Int64) {
        if case .downloading = statuses[id] {
            statuses[id] = .downloading(received: received, total: total)
        }
    }

    private func handleFailure(id: String, error: Error) {
        tasks[id] = nil
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        if let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            storeResumeData(resume, id: id)
        }
        statuses[id] = .failed(error.localizedDescription)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            updateProgress(id: id, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // URLSession deletes `location` when this returns, so claim it now.
        let kept = location.deletingLastPathComponent().appending(path: "\(id).part")
        try? FileManager.default.removeItem(at: kept)
        guard (try? FileManager.default.moveItem(at: location, to: kept)) != nil else { return }
        Task { @MainActor in
            tasks[id] = nil
            try? FileManager.default.removeItem(at: resumeFile(id))
            await install(kept, id: id)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        Task { @MainActor in handleFailure(id: id, error: error) }
    }
}
