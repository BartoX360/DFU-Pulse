import SwiftUI

/// Download state for one release, shared by the flash and library pages.
struct DownloadControl: View {
    @Environment(AppModel.self) private var model
    let firmware: Firmware

    var body: some View {
        switch model.downloads.statuses[firmware.id] {
        case .downloading(let received, let total):
            HStack(spacing: 8) {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                    .frame(width: 110)
                Text(verbatim: "\(received.fileSize) / \(total.fileSize)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Pause", systemImage: "pause.fill") { model.downloads.pause(firmware.id) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        case .verifying(let value):
            HStack(spacing: 8) {
                ProgressView(value: value).frame(width: 110)
                Text("Verifying…").font(.caption).foregroundStyle(.secondary)
            }
        case .paused:
            HStack(spacing: 8) {
                Button("Resume") { model.downloads.start(firmware) }
                Button("Discard", systemImage: "xmark") { model.downloads.discard(firmware.id) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                Button("Retry") { model.downloads.start(firmware) }
            }
        case nil:
            Button("Download", systemImage: "arrow.down.circle") { model.downloads.start(firmware) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title3)
                .help("Download")
        }
    }
}
