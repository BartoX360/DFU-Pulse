import AppKit
import CryptoKit
import Foundation
import Observation

/// The folder holding IPSW files. Lives in Application Support rather than
/// Caches because macOS may purge Caches and these files take hours to fetch.
@MainActor @Observable
final class IPSWLibrary {
    private static let folderKey = "libraryFolder"

    private(set) var items: [LibraryItem] = []
    private(set) var folder: URL

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.folderKey) {
            folder = URL(filePath: saved, directoryHint: .isDirectory)
        } else {
            folder = URL.applicationSupportDirectory.appending(path: "DFU Pulse/IPSW", directoryHint: .isDirectory)
        }
        refresh()
    }

    func refresh() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let found: [LibraryItem] = files.filter { $0.pathExtension.lowercased() == "ipsw" }.map(Self.item(at:))
        items = found.sorted { lhs, rhs in
            (lhs.version ?? "").compare(rhs.version ?? "", options: .numeric) == .orderedDescending
        }
    }

    /// The file for a release. A macOS image may have been renamed on import;
    /// iPhone and iPad images share builds, so only the name tells them apart.
    func item(for firmware: Firmware) -> LibraryItem? {
        items.first { $0.name == firmware.fileName }
            ?? items.first { !$0.kind.isMobile && firmware.system == "macOS" && $0.build == firmware.build }
    }

    func setFolder(_ url: URL) {
        folder = url
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.folderKey)
        refresh()
    }

    func trash(_ item: LibraryItem) throws {
        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        refresh()
    }

    /// Copies files off the main actor: an IPSW weighs more than 15 GB.
    func importFiles(_ urls: [URL]) async throws {
        let folder = folder
        try await Task.detached {
            for url in urls where url.pathExtension.lowercased() == "ipsw" {
                let destination = folder.appending(path: url.lastPathComponent)
                guard url.standardizedFileURL != destination.standardizedFileURL else { continue }
                try FileManager.default.copyItem(at: url, to: destination)
            }
        }.value
        refresh()
    }

    private nonisolated static func item(at url: URL) -> LibraryItem {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let parsed = IPSWName.parse(url.lastPathComponent)
        return LibraryItem(url: url, size: Int64(values?.fileSize ?? 0),
                           modified: values?.contentModificationDate ?? .distantPast,
                           version: parsed?.version, build: parsed?.build)
    }
}

enum IPSWVerifier {
    /// Hashes a file in chunks and compares it with the catalog's checksum.
    /// Returns nil when the catalog gave none.
    static func verify(_ url: URL, firmware: Firmware,
                       onProgress: @Sendable @escaping (Double) -> Void) async throws -> Bool? {
        guard firmware.sha256 != nil || firmware.sha1 != nil else { return nil }
        return try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let total = Double((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1)
            var sha256 = SHA256()
            var sha1 = Insecure.SHA1()
            let useSHA256 = firmware.sha256 != nil
            var done = 0.0
            while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
                try Task.checkCancellation()
                if useSHA256 { sha256.update(data: chunk) } else { sha1.update(data: chunk) }
                done += Double(chunk.count)
                onProgress(min(done / total, 1))
            }
            let digest = useSHA256
                ? sha256.finalize().map { String(format: "%02x", $0) }.joined()
                : sha1.finalize().map { String(format: "%02x", $0) }.joined()
            return digest.caseInsensitiveCompare(firmware.sha256 ?? firmware.sha1 ?? "") == .orderedSame
        }.value
    }
}
