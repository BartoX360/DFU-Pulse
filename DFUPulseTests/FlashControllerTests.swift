import Foundation
import Testing
@testable import DFU_Pulse

/// Drives FlashController against a stand-in for cfgutil.
@MainActor @Suite(.serialized) struct FlashControllerTests {
    private func fakeTool(exitCode: Int) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "fake-cfgutil-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        echo "args: $*"
        echo "Restoring 40%"
        echo "Restoring 100%"
        exit \(exitCode)
        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        setenv("DFUPULSE_CFGUTIL", url.path, 1)
        return url
    }

    private func waitForEnd(_ flash: FlashController) async {
        for _ in 0..<100 where flash.isRunning {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func reportsProgressAndSuccess() async throws {
        let tool = try fakeTool(exitCode: 0)
        defer { try? FileManager.default.removeItem(at: tool) }
        let flash = FlashController()
        let target = TargetDevice(ecid: "0x1", model: "Mac14,2", name: nil, location: nil)
        flash.start(mode: .restore, target: target, ipsw: URL(filePath: "/tmp/x.ipsw"))
        #expect(flash.isRunning)
        await waitForEnd(flash)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(flash.state == .succeeded)
        #expect(flash.progress == 1)
        #expect(flash.log.first == "args: --progress -e 0x1 restore -I /tmp/x.ipsw")
    }

    @Test func reportsFailure() async throws {
        let tool = try fakeTool(exitCode: 3)
        defer { try? FileManager.default.removeItem(at: tool) }
        let flash = FlashController()
        let target = TargetDevice(ecid: "0x1", model: "Mac14,2", name: nil, location: nil)
        flash.start(mode: .revive, target: target, ipsw: nil)
        await waitForEnd(flash)
        #expect(flash.state == .failed(3))
    }
}
