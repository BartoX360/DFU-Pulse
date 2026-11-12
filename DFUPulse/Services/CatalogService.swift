import Foundation
import Observation

/// The macOS restore images for Apple silicon Macs. Since macOS 12 every Mac
/// uses the same "UniversalMac" IPSW for a given build; only the list of Macs
/// a build supports differs. ipsw.me provides the full history and SHA-256
/// sums, Apple's own feed covers the current build when ipsw.me is down.
/// iPhone and iPad images fit only a few models each, so they are fetched
/// one model at a time, when needed.
@MainActor @Observable
final class CatalogService {
    private(set) var releases: [Firmware] = []
    private(set) var names: [String: String] = [:]
    private(set) var mobileReleases: [String: [Firmware]] = [:]
    private(set) var loadingModels: Set<String> = []
    private(set) var isLoading = false
    private(set) var failure: String?

    private let cacheURL = URL.applicationSupportDirectory.appending(path: "DFU Pulse/catalog.json")

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Cache.self, from: data) {
            releases = cached.releases
            names = cached.names
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (names, list) = try await Self.fetch()
            releases = list
            if !names.isEmpty { self.names = names }
            failure = nil
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(Cache(releases: list, names: self.names)).write(to: cacheURL)
        } catch {
            failure = error.localizedDescription
        }
    }

    func releases(for model: String) -> [Firmware] {
        if DeviceKind(model: model).isMobile { return mobileReleases[model] ?? [] }
        return releases.filter { $0.models.contains(model) }
    }

    /// Signed iOS or iPadOS images for one model, newest first.
    func loadReleases(for model: String) async {
        guard DeviceKind(model: model).isMobile, !loadingModels.contains(model) else { return }
        loadingModels.insert(model)
        defer { loadingModels.remove(model) }
        do {
            mobileReleases[model] = Self.merge(try await Self.fetchIPSWMe(model: model))
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// The release a file on disk comes from, when Apple still signs it.
    func firmware(for item: LibraryItem) -> Firmware? {
        if item.kind.isMobile {
            return mobileReleases.values.lazy.flatMap(\.self).first { $0.fileName == item.name }
        }
        return releases.first { $0.fileName == item.name } ?? releases.first { $0.build == item.build }
    }

    /// iPhone or iPad models, newest first. Names follow no common scheme
    /// ("iPad 8", "iPad (A16)", "iPhone XS"), so they are ordered by identifier.
    func models(of kind: DeviceKind) -> [String] {
        Self.newestFirst(names.keys.filter { DeviceKind(prefixOf: $0) == kind })
    }

    /// "iPad11,6" sorts as [11, 6].
    nonisolated static func newestFirst(_ models: [String]) -> [String] {
        func generation(_ model: String) -> [Int] { model.split { !$0.isNumber }.compactMap { Int($0) } }
        return models.sorted { generation($1).lexicographicallyPrecedes(generation($0)) }
    }

    /// The iPad line a model belongs to, used to group the model list.
    nonisolated static func family(of name: String) -> String {
        ["iPad Pro", "iPad Air", "iPad mini"].first { name.hasPrefix($0) } ?? "iPad"
    }

    nonisolated static let iPadFamilies = ["iPad Pro", "iPad Air", "iPad", "iPad mini"]

    func displayName(for model: String) -> String {
        names[model] ?? model
    }

    private struct Cache: Codable {
        let releases: [Firmware]
        let names: [String: String]
    }

    // MARK: Fetching

    private nonisolated static func fetch() async throws -> ([String: String], [Firmware]) {
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.ipsw.me/v4/devices")!)
            let names = deviceNames(from: try JSONDecoder().decode([DeviceDTO].self, from: data))
            let perModel = await withTaskGroup(of: [Firmware].self) { group in
                var pending = names.keys.filter { $0.hasPrefix("Mac") }.sorted()[...]
                var results: [[Firmware]] = []
                // A handful of requests at a time keeps ipsw.me happy; one
                // failing model only loses that model's entries.
                for _ in 0..<8 {
                    guard let model = pending.popFirst() else { break }
                    group.addTask { (try? await fetchIPSWMe(model: model)) ?? [] }
                }
                while let list = await group.next() {
                    results.append(list)
                    if let model = pending.popFirst() {
                        group.addTask { (try? await fetchIPSWMe(model: model)) ?? [] }
                    }
                }
                return results
            }
            let merged = merge(perModel.flatMap { $0 })
            if !merged.isEmpty { return (names, merged) }
        } catch {}
        let url = URL(string: "https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return ([:], try parseAppleFeed(data))
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
            let identifier: String
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

    /// Macs, iPhones and iPads; iBridge and other accessories are left out.
    nonisolated static func deviceNames(from devices: [DeviceDTO]) -> [String: String] {
        let kept = devices.filter {
            guard let kind = DeviceKind(prefixOf: $0.identifier) else { return false }
            return kind != .t2
        }
        return Dictionary(kept.map { ($0.identifier, $0.name) }) { first, _ in first }
    }

    /// Only signed builds: Apple refuses to install the others.
    nonisolated static func parseIPSWMe(_ data: Data) throws -> [Firmware] {
        let dates = ISO8601DateFormatter()
        return try JSONDecoder().decode(DeviceFirmwaresDTO.self, from: data).firmwares
            .filter { $0.signed && TrustedSource.isApple($0.url) }
            .map {
                Firmware(version: $0.version, build: $0.buildid, url: $0.url,
                         sha256: $0.sha256sum, sha1: $0.sha1sum, size: $0.filesize,
                         releaseDate: $0.releasedate.flatMap(dates.date(from:)), models: [$0.identifier])
            }
    }

    /// Folds per-model entries into one release per build.
    nonisolated static func merge(_ entries: [Firmware]) -> [Firmware] {
        var byBuild: [String: Firmware] = [:]
        for entry in entries {
            if var existing = byBuild[entry.build] {
                existing.models.formUnion(entry.models)
                byBuild[entry.build] = existing
            } else {
                byBuild[entry.build] = entry
            }
        }
        return byBuild.values.sorted {
            $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }
    }

    /// Apple's feed only lists the build it currently ships, per model.
    nonisolated static func parseAppleFeed(_ data: Data) throws -> [Firmware] {
        let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let versions = root?["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any]
        var entries: [Firmware] = []
        for case let group as [String: Any] in versions?.values.map({ $0 }) ?? [] {
            let models = group["MobileDeviceSoftwareVersions"] as? [String: Any] ?? [:]
            for (model, value) in models {
                guard let builds = value as? [String: Any] else { continue }
                for case let entry as [String: Any] in builds.values {
                    guard let restore = entry["Restore"] as? [String: Any],
                          let build = restore["BuildVersion"] as? String,
                          let version = restore["ProductVersion"] as? String,
                          let link = restore["FirmwareURL"] as? String,
                          let url = URL(string: link), TrustedSource.isApple(url) else { continue }
                    entries.append(Firmware(version: version, build: build, url: url, sha256: nil,
                                            sha1: restore["FirmwareSHA1"] as? String, size: nil,
                                            releaseDate: nil, models: [model]))
                }
            }
        }
        return merge(entries)
    }
}
