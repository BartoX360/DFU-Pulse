import Foundation
import Testing
@testable import DFU_Pulse

@Suite struct ParsingTests {
    @Test func readsIPSWFileName() {
        let parsed = IPSWName.parse("UniversalMac_27.2_26B123_Restore.ipsw")
        #expect(parsed?.version == "27.2")
        #expect(parsed?.build == "26B123")
        #expect(IPSWName.parse("notes.ipsw") == nil)
    }

    @Test func onlyTrustsAppleHosts() {
        #expect(TrustedSource.isApple(URL(string: "https://updates.cdn-apple.com/a.ipsw")!))
        #expect(TrustedSource.isApple(URL(string: "https://swcdn.apple.com/a.ipsw")!))
        #expect(!TrustedSource.isApple(URL(string: "http://updates.cdn-apple.com/a.ipsw")!))
        #expect(!TrustedSource.isApple(URL(string: "https://updates.cdn-apple.com.evil.net/a.ipsw")!))
        #expect(!TrustedSource.isApple(URL(string: "https://notapple.com/a.ipsw")!))
    }

    @Test func dropsCatalogEntriesNotHostedByApple() throws {
        let json = """
        {"firmwares":[
         {"version":"27.2","buildid":"26B123","url":"https://updates.cdn-apple.com/x_27.2_26B123_Restore.ipsw",
          "sha256sum":"ab","sha1sum":"cd","filesize":10,"releasedate":"2026-10-26T18:14:20Z","signed":true},
         {"version":"27.1","buildid":"26B1","url":"https://evil.example/x.ipsw","signed":true}
        ]}
        """
        let list = try CatalogService.parseIPSWMe(Data(json.utf8))
        #expect(list.map(\.build) == ["26B123"])
        #expect(list[0].releaseDate != nil)
    }

    @Test func readsAppleFeed() throws {
        let feed: [String: Any] = ["MobileDeviceSoftwareVersionsByVersion": ["1": ["MobileDeviceSoftwareVersions": ["Mac14,2": [
            "26B123": ["Restore": [
                "FirmwareURL": "https://updates.cdn-apple.com/x.ipsw", "FirmwareSHA1": "aa",
                "ProductVersion": "27.2", "BuildVersion": "26B123",
            ]],
            "Unknown": ["Universal": ["Restore": ["BuildVersion": "26B123"]]],
        ]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: feed, format: .xml, options: 0)
        let list = try CatalogService.parseAppleFeed(data, model: "Mac14,2")
        #expect(list.count == 1)
        #expect(list[0].sha1 == "aa")
        #expect(try CatalogService.parseAppleFeed(data, model: "Mac99,9").isEmpty)
    }

    @Test func listsOnlyMacsFromCfgutil() {
        let json = """
        {"Command":"list","Type":"CommandOutput","Devices":["0x1","0x2"],"Output":{
         "0x1":{"ECID":"0x1","deviceType":"Mac14,2","name":null,"locationID":4194304,"UDID":null},
         "0x2":{"ECID":"0x2","deviceType":"iPhone15,2","name":"Phone"},
         "0x3":{"ECID":"0x3","deviceType":"iBridge2,1"}
        }}
        """
        let devices = Configurator.parseDevices(Data(json.utf8))
        #expect(devices.map(\.ecid) == ["0x1", "0x3"])
        #expect(devices[1].isT2)
        #expect(Configurator.parseDevices(Data("nope".utf8)).isEmpty)
    }

    @Test func buildsCfgutilArguments() {
        let ipsw = URL(filePath: "/tmp/a b.ipsw")
        #expect(Configurator.arguments(mode: .restore, ecid: "0x1", ipsw: ipsw)
            == ["--progress", "-e", "0x1", "restore", "-I", "/tmp/a b.ipsw"])
        #expect(Configurator.arguments(mode: .revive, ecid: "0x1", ipsw: ipsw)
            == ["--progress", "-e", "0x1", "revive"])
    }

    @Test func readsProgress() {
        #expect(Configurator.progress(in: "Restoring 42.5%") == 0.425)
        #expect(Configurator.progress(in: "Waiting") == nil)
        #expect(Configurator.progress(in: "999%") == nil)
    }

    @Test func verifiesChecksums() async throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        func firmware(sha256: String?) -> Firmware {
            Firmware(version: "1", build: "1A1", url: url, sha256: sha256, sha1: nil,
                     size: nil, releaseDate: nil, signed: true)
        }
        let good = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        #expect(try await IPSWVerifier.verify(url, firmware: firmware(sha256: good)) { _ in } == true)
        #expect(try await IPSWVerifier.verify(url, firmware: firmware(sha256: "00")) { _ in } == false)
        #expect(try await IPSWVerifier.verify(url, firmware: firmware(sha256: nil)) { _ in } == nil)
    }
}
