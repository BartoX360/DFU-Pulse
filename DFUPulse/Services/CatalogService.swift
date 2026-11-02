import Foundation
import Observation

/// Lists Mac models and their restore images: ipsw.me first for its full
/// history and SHA-256 sums, Apple's own feed when ipsw.me is unreachable.
@MainActor @Observable
final class CatalogService {
    private(set) var macNames: [String: String] = [:]
    private(set) var firmwares: [String: [Firmware]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var failures: [String: String] = [:]

    func loadModels() async {
        guard macNames.isEmpty else { return }
        guard let url = URL(string: "https://api.ipsw.me/v4/devices"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let devices = try? JSONDecoder().decode([DeviceDTO].self, from: data) else { return }
        macNames = Self.macNames(from: devices)
    }

    func load(model: String) async {
        guard firmwares[model] == nil, !loading.contains(model) else { return }
        loading.insert(model)
        defer { loading.remove(model) }
        failures[model] = nil
        do {
            firmwares[model] = try await Self.fetch(model: model)
        } catch {
            failures[model] = error.localizedDescription
        }
    }

    func firmware(build: String) -> Firmware? {
        firmwares.values.lazy.flatMap { $0 }.first { $0.build == build }
    }

    func displayName(for model: String) -> String {
        macNames[model] ?? model
    }

    private nonisolated static func fetch(model: String) async throws -> [Firmware] {
        if let list = try? await fetchIPSWMe(model: model), !list.isEmpty {
            return list
        }
        let url = URL(string: "https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseAppleFeed(data, model: model)
    }

    private nonisolated static func fetchIPSWMe(model: String) async throws -> [Firmware] {
        var components = URLComponents(string: "https://api.ipsw.me/v4/device/")!
        components.path += model
        components.queryItems = [URLQueryItem(name: "type", value: "ipsw")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try parseIPSWMe(data)
    }

    // MARK: Parsing

    nonisolated struct DeviceDTO: Decodable {
        let name: String
        let identifier: String
    }

    private nonisolated struct DeviceFirmwaresDTO: Decodable {
        struct Item: Decodable {
            let version: String
            let buildid: String
            let url: URL
            let sha256sum: String?
            let sha1sum: String?
            let filesize: Int64?
            let releasedate: String?
            let signed: Bool
        }
        let firmwares: [Item]
    }

    nonisolated static func macNames(from devices: [DeviceDTO]) -> [String: String] {
        let macs = devices.filter { $0.identifier.hasPrefix("Mac") }
        return Dictionary(macs.map { ($0.identifier, $0.name) }) { first, _ in first }
    }

    nonisolated static func parseIPSWMe(_ data: Data) throws -> [Firmware] {
        let dates = ISO8601DateFormatter()
        return try JSONDecoder().decode(DeviceFirmwaresDTO.self, from: data).firmwares
            .filter { TrustedSource.isApple($0.url) }
            .map {
                Firmware(version: $0.version, build: $0.buildid, url: $0.url,
                         sha256: $0.sha256sum, sha1: $0.sha1sum, size: $0.filesize,
                         releaseDate: $0.releasedate.flatMap(dates.date(from:)), signed: $0.signed)
            }
    }

    /// Apple's feed only lists images it still signs, keyed by build.
    nonisolated static func parseAppleFeed(_ data: Data, model: String) throws -> [Firmware] {
        let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let versions = root?["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any]
        var results: [String: Firmware] = [:]
        for case let group as [String: Any] in versions?.values.map({ $0 }) ?? [] {
            let models = group["MobileDeviceSoftwareVersions"] as? [String: Any]
            guard let builds = models?[model] as? [String: Any] else { continue }
            for case let entry as [String: Any] in builds.values {
                guard let restore = entry["Restore"] as? [String: Any],
                      let build = restore["BuildVersion"] as? String,
                      let version = restore["ProductVersion"] as? String,
                      let link = restore["FirmwareURL"] as? String,
                      let url = URL(string: link), TrustedSource.isApple(url) else { continue }
                results[build] = Firmware(version: version, build: build, url: url, sha256: nil,
                                          sha1: restore["FirmwareSHA1"] as? String, size: nil,
                                          releaseDate: nil, signed: true)
            }
        }
        return results.values.sorted {
            $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }
    }
}
