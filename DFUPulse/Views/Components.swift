import SwiftUI

/// An electrocardiogram line, the app's "pulse".
struct PulseLine: Shape {
    var phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let period = rect.width / 2
        for x in stride(from: CGFloat(0), through: rect.width, by: 1) {
            let t = ((x / period) + phase).truncatingRemainder(dividingBy: 1)
            let y = midY - beat(t) * rect.height / 2
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func beat(_ t: CGFloat) -> CGFloat {
        switch t {
        case 0.40..<0.45: (t - 0.40) / 0.05 * -0.25
        case 0.45..<0.50: -0.25 + (t - 0.45) / 0.05 * 1.25
        case 0.50..<0.56: 1 - (t - 0.50) / 0.06 * 1.6
        case 0.56..<0.60: -0.6 + (t - 0.56) / 0.04 * 0.6
        default: 0
        }
    }
}

struct AnimatedPulse: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            PulseLine(phase: CGFloat(time.truncatingRemainder(dividingBy: 2.4) / 2.4))
                .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Download state for one release, shared by the flash and library pages.
struct DownloadControl: View {
    @Environment(AppModel.self) private var model
    let firmware: Firmware

    var body: some View {
        switch model.downloads.statuses[firmware.build] {
        case .downloading(let received, let total):
            HStack(spacing: 8) {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                    .frame(width: 110)
                Text(verbatim: "\(received.fileSize) / \(total.fileSize)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Pause", systemImage: "pause.fill") { model.downloads.pause(firmware.build) }
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
                Button("Discard", systemImage: "xmark") { model.downloads.discard(firmware.build) }
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
