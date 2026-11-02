import SwiftUI

/// The app's backdrop: the deep blues of the logo, for the glass to refract.
struct PulseBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.06, blue: 0.14)
            RadialGradient(colors: [Color(red: 0.05, green: 0.45, blue: 0.75).opacity(0.55), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color(red: 0.38, green: 0.22, blue: 0.85).opacity(0.35), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

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
    var color: Color = .cyan

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            PulseLine(phase: CGFloat(time.truncatingRemainder(dividingBy: 2.4) / 2.4))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.8), radius: 6)
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct PageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

struct Badge: View {
    let text: LocalizedStringKey
    var tint: Color = .cyan

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
    }
}

/// Download state for one firmware, shared by the flash and library pages.
struct DownloadControl: View {
    @Environment(AppModel.self) private var model
    let firmware: Firmware

    var body: some View {
        switch model.downloads.statuses[firmware.build] {
        case .downloading(let received, let total):
            HStack(spacing: 10) {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                    .frame(width: 130)
                Text(verbatim: "\(received.fileSize) / \(total.fileSize)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Pause", systemImage: "pause.fill") { model.downloads.pause(firmware.build) }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }
        case .verifying(let value):
            HStack(spacing: 10) {
                ProgressView(value: value).frame(width: 130)
                Text("Verifying…").font(.caption).foregroundStyle(.secondary)
            }
        case .paused:
            HStack(spacing: 8) {
                Button("Resume", systemImage: "play.fill") { model.downloads.start(firmware) }
                    .buttonStyle(.glass)
                Button("Discard", systemImage: "xmark") { model.downloads.discard(firmware.build) }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                Button("Retry", systemImage: "arrow.clockwise") { model.downloads.start(firmware) }
                    .buttonStyle(.glass)
            }
        case nil:
            Button("Download", systemImage: "arrow.down") { model.downloads.start(firmware) }
                .buttonStyle(.glass)
        }
    }
}
