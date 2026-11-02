import SwiftUI

struct GuideView: View {
    @State private var platform: DeviceKind = .mac
    @State private var family = PortFamily.all[5]
    @State private var mobile = MobileFamily.all[0]

    var body: some View {
        Group {
            if platform.isMobile {
                mobileGuide
            } else {
                macGuide
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Port guide")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Platform", selection: $platform) {
                    Text(verbatim: "Mac").tag(DeviceKind.mac)
                    Text(verbatim: "iPhone & iPad").tag(DeviceKind.iPhone)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var mobileGuide: some View {
        Form {
            Section {
                Picker("Device to flash", selection: $mobile) {
                    ForEach(MobileFamily.all) { item in
                        Text(verbatim: "\(item.product) — \(String(localized: item.detail))").tag(item)
                    }
                }
            } footer: {
                Text("iPhones and iPads have no DFU port: plug any data cable into this Mac. They enter DFU with their buttons only.")
                    .foregroundStyle(.secondary)
            }

            Section("Enter DFU") {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: mobile.symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(([LocalizedStringResource("Connect the device to this Mac with a cable that carries data.")] + mobile.steps).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: "\(index + 1).")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Text(step)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                Text("In DFU mode the screen stays black. If the Apple logo appears, a button was held too long: start again.")
                    .foregroundStyle(.secondary)
                Text("If the screen shows a computer and a cable, the device is in recovery mode: it can be restored too.")
                    .foregroundStyle(.secondary)
            }

            Section("Restore") {
                Text("Restoring erases the device. If Activation Lock is on, its Apple Account password is needed afterwards.")
            }
        }
    }

    private var macGuide: some View {
        Form {
            Section {
                Picker("Mac to flash", selection: $family) {
                    ForEach(PortFamily.products, id: \.self) { product in
                        Section(product) {
                            ForEach(PortFamily.all.filter { $0.product == product }) { item in
                                Text(verbatim: "\(item.product) — \(String(localized: item.detail))").tag(item)
                            }
                        }
                    }
                }
            } footer: {
                Text("Only one USB-C port accepts DFU, and it depends on the Mac.")
                    .foregroundStyle(.secondary)
            }

            Section("DFU port") {
                PortDiagram(family: family)
                Text(family.location)
            }

            Section("Enter DFU by hand") {
                ForEach(Array(family.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1).")
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(step)
                    }
                }
                Text("If this Mac asks to allow the accessory, click Allow.")
                    .foregroundStyle(.secondary)
            }

            Section("Cable") {
                Text("Use a USB-C cable that carries data and charging. Thunderbolt 3 cables are not supported.")
                Text("By hand, any USB-C port works on this Mac. Automatic entry needs its DFU port too.")
                Link("Apple's reference table", destination: URL(string: "https://support.apple.com/120694")!)
            }
        }
    }
}

/// The face of the Mac that holds the DFU port, drawn as a row of USB-C ports.
/// Laptops are seen from the left side (hinge on the left); desktops from the
/// back. When the port count varies by model, the middle ports are elided.
struct PortDiagram: View {
    let family: PortFamily

    private enum Slot: Hashable { case port(Int), gap }

    private var slots: [Slot] {
        guard let count = family.ports else { return [.port(0), .gap, .port(1)] }
        return (0..<count).map(Slot.port)
    }

    private func isDFU(_ index: Int) -> Bool {
        let count = family.ports ?? 2
        switch family.position {
        case .first: return index == 0
        case .middle: return index == count / 2
        case .last: return index == count - 1
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(systemName: family.symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64)

            if family.note == nil {
                VStack(spacing: 8) {
                    HStack(spacing: 14) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                            switch slot {
                            case .port(let index):
                                let dfu = isDFU(index)
                                VStack(spacing: 6) {
                                    Capsule()
                                        .strokeBorder(dfu ? Color.accentColor : .secondary.opacity(0.6), lineWidth: 1.5)
                                        .background(Capsule().fill(dfu ? Color.accentColor.opacity(0.25) : .clear))
                                        .frame(width: 36, height: 12)
                                    Text(verbatim: "DFU")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .opacity(dfu ? 1 : 0)
                                }
                            case .gap:
                                Text(verbatim: "···").foregroundStyle(.secondary).padding(.bottom, 18)
                            }
                        }
                    }
                    HStack {
                        Text(family.isLaptop ? "Hinge" : "Left")
                        Spacer()
                        Text(family.isLaptop ? "Front" : "Right")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
