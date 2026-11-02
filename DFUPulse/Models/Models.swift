import Foundation

/// A macOS restore image, shared by every Mac model it supports.
struct Firmware: Identifiable, Hashable, Codable, Sendable {
    let version: String
    let build: String
    let url: URL
    let sha256: String?
    let sha1: String?
    let size: Int64?
    let releaseDate: Date?
    var models: Set<String>

    var id: String { build }
    var fileName: String { url.lastPathComponent }
    var major: String { String(version.prefix { $0 != "." }) }
}

/// A Mac seen by Apple Configurator, usually in DFU mode.
struct TargetDevice: Identifiable, Hashable, Sendable {
    let ecid: String
    let model: String
    let name: String?
    let location: String?

    var id: String { ecid }
    /// T2 Macs show up as their bridge chip and cannot take a macOS IPSW.
    var isT2: Bool { model.hasPrefix("iBridge") }
}

enum RestoreMode: String, CaseIterable, Identifiable, Sendable {
    case revive
    case restore

    var id: String { rawValue }
}

/// An IPSW file on disk.
struct LibraryItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date
    let version: String?
    let build: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum IPSWName {
    /// Reads "UniversalMac_27.2_26B123_Restore.ipsw".
    static func parse(_ fileName: String) -> (version: String, build: String)? {
        guard let match = fileName.firstMatch(of: /_(\d+(?:\.\d+)*)_(\d+[A-Z]+\d+[a-z]?)_Restore/) else {
            return nil
        }
        return (String(match.1), String(match.2))
    }
}

/// Only Apple hosts may serve a file we are about to install on a Mac,
/// whatever a third-party catalog says.
enum TrustedSource {
    static func isApple(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com") || host.hasSuffix(".cdn-apple.com")
    }
}

extension Int64 {
    var fileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
