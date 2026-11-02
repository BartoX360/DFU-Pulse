import Foundation

/// A restore image. A macOS one is shared by every Mac model it supports;
/// an iOS or iPadOS one only fits a few devices, so the file name identifies it.
struct Firmware: Identifiable, Hashable, Codable, Sendable {
    let version: String
    let build: String
    let url: URL
    let sha256: String?
    let sha1: String?
    let size: Int64?
    let releaseDate: Date?
    var models: Set<String>

    var id: String { fileName }
    var fileName: String { url.lastPathComponent }
    var system: String { DeviceKind(model: models.first ?? "").system }
    var major: String { String(version.prefix { $0 != "." }) }
}

/// The family of a model identifier such as "Mac16,1" or "iPhone17,3".
enum DeviceKind: Hashable, Sendable {
    case mac, t2, iPhone, iPad

    init?(prefixOf model: String) {
        if model.hasPrefix("Mac") { self = .mac }
        else if model.hasPrefix("iBridge") { self = .t2 }
        else if model.hasPrefix("iPhone") { self = .iPhone }
        else if model.hasPrefix("iPad") { self = .iPad }
        else { return nil }
    }

    init(model: String) {
        self = DeviceKind(prefixOf: model) ?? .mac
    }

    var isMobile: Bool { self == .iPhone || self == .iPad }

    var system: String {
        switch self {
        case .mac, .t2: "macOS"
        case .iPhone: "iOS"
        case .iPad: "iPadOS"
        }
    }
}

/// A device seen by Apple Configurator, usually in DFU mode.
struct TargetDevice: Identifiable, Hashable, Sendable {
    let ecid: String
    let model: String
    let name: String?
    let location: String?

    var id: String { ecid }
    var kind: DeviceKind { DeviceKind(model: model) }
    /// T2 Macs show up as their bridge chip and cannot take a macOS IPSW.
    var isT2: Bool { kind == .t2 }
    var isMobile: Bool { kind.isMobile }
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
    /// iOS and iPadOS files start with the model they fit, macOS ones with "UniversalMac".
    var kind: DeviceKind { DeviceKind(model: name) }
}

enum IPSWName {
    /// Reads "UniversalMac_27.2_26B123_Restore.ipsw" or "iPhone17,3_27.2_24B83_Restore.ipsw".
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
