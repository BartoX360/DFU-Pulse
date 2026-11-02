import SwiftUI

struct GuideView: View {
    @State private var family = PortFamily.all[2]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Port guide", subtitle: "Only one USB-C port accepts DFU, and it depends on the Mac.")

                GlassCard {
                    Picker("Mac being flashed", selection: $family) {
                        ForEach(PortFamily.all) { item in
                            Text(verbatim: "\(item.product) — \(String(localized: item.detail))").tag(item)
                        }
                    }
                    PortDiagram(family: family)
                    Text(portSentence).font(.headline)
                    Text("The port diagram is schematic: the number of ports varies by model.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GlassCard {
                    Text("Enter DFU by hand").font(.headline)
                    ForEach(Array(family.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: "\(index + 1)")
                                .font(.callout.bold().monospacedDigit()).foregroundStyle(.cyan)
                            Text(step)
                        }
                    }
                    Text("If this Mac asks to allow the accessory, click Allow.")
                        .foregroundStyle(.secondary)
                }

                GlassCard {
                    Text("Cable and connection").font(.headline)
                    Label("Use a USB-C cable that carries data and charging. Thunderbolt 3 cables are not supported.", systemImage: "cable.connector")
                    Label("By hand, any USB-C port works on this Mac. Automatic entry needs its DFU port too.", systemImage: "bolt.horizontal")
                    Label("Keep both Macs on power and this Mac awake.", systemImage: "powerplug.fill")
                    Link("Apple's reference table", destination: URL(string: "https://support.apple.com/120694")!)
                        .font(.callout)
                }
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var portSentence: LocalizedStringResource {
        if let note = family.note { return note }
        switch (family.position, family.side) {
        case (.leftmost, .back): return "Leftmost USB-C port, seen from the back"
        case (.middle, .back): return "Middle USB-C port, seen from the back"
        case (.rightmost, .back): return "Rightmost USB-C port, seen from the back"
        case (.rightmost, _): return "Rightmost USB-C port, seen from the left side"
        default: return "Leftmost USB-C port, seen from the left side"
        }
    }
}

/// Draws three ports and lights up the DFU one.
struct PortDiagram: View {
    let family: PortFamily

    private var highlighted: Int {
        switch family.position {
        case .leftmost: 0
        case .middle: 1
        case .rightmost: 2
        }
    }

    var body: some View {
        HStack(spacing: 26) {
            ForEach(0..<3, id: \.self) { index in
                VStack(spacing: 8) {
                    Capsule()
                        .fill(index == highlighted ? Color.cyan : Color.white.opacity(0.14))
                        .frame(width: 58, height: 18)
                        .shadow(color: index == highlighted ? .cyan : .clear, radius: 10)
                    Text(verbatim: index == highlighted ? "DFU" : " ")
                        .font(.caption.bold()).foregroundStyle(.cyan)
                }
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
        .animation(.smooth, value: highlighted)
        .accessibilityHidden(true)
    }
}
