import Foundation

/// Where the DFU port sits, from Apple's "How to identify the DFU port on Mac".
struct PortFamily: Identifiable, Hashable, Sendable {
    enum Position: Sendable { case leftmost, middle, rightmost }
    enum Side: Sendable { case left, back, top, front }
    enum Kind: Sendable { case laptop, laptopT2, desktop }

    let id: String
    let product: String
    let detail: LocalizedStringResource
    let position: Position
    let side: Side
    let kind: Kind
    /// Replaces the left/middle/right wording on Mac Pro.
    var note: LocalizedStringResource? = nil

    static func == (lhs: PortFamily, rhs: PortFamily) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PortFamily {
    static let all: [PortFamily] = [
        .init(id: "neo", product: "MacBook Neo", detail: "All models",
              position: .leftmost, side: .left, kind: .laptop),
        .init(id: "mbp-base", product: "MacBook Pro", detail: "14-inch M4 or M5 (not Pro or Max)",
              position: .rightmost, side: .left, kind: .laptop),
        .init(id: "mbp-as", product: "MacBook Pro", detail: "Other Apple silicon models",
              position: .leftmost, side: .left, kind: .laptop),
        .init(id: "mbp-t2", product: "MacBook Pro", detail: "T2 chip",
              position: .rightmost, side: .left, kind: .laptopT2),
        .init(id: "mba-2025", product: "MacBook Air", detail: "Apple silicon, 2025 or later",
              position: .rightmost, side: .left, kind: .laptop),
        .init(id: "mba-as", product: "MacBook Air", detail: "Earlier Apple silicon models",
              position: .leftmost, side: .left, kind: .laptop),
        .init(id: "mba-t2", product: "MacBook Air", detail: "T2 chip",
              position: .rightmost, side: .left, kind: .laptopT2),
        .init(id: "imac", product: "iMac", detail: "All models",
              position: .rightmost, side: .back, kind: .desktop),
        .init(id: "mini-2025", product: "Mac mini", detail: "Apple silicon, 2025 or later",
              position: .middle, side: .back, kind: .desktop),
        .init(id: "mini-as", product: "Mac mini", detail: "Earlier Apple silicon models",
              position: .leftmost, side: .back, kind: .desktop),
        .init(id: "mini-t2", product: "Mac mini", detail: "T2 chip",
              position: .rightmost, side: .back, kind: .desktop),
        .init(id: "studio", product: "Mac Studio", detail: "All models",
              position: .rightmost, side: .back, kind: .desktop),
        .init(id: "pro-tower", product: "Mac Pro", detail: "Tower enclosure",
              position: .rightmost, side: .top, kind: .desktop,
              note: "On top, the USB-C port farthest from the power button"),
        .init(id: "pro-rack", product: "Mac Pro", detail: "Rack enclosure",
              position: .leftmost, side: .front, kind: .desktop,
              note: "On the front, the USB-C port closest to the power button"),
    ]

    var steps: [LocalizedStringResource] {
        switch kind {
        case .laptop:
            [
                "Plug the cable into the DFU port. Leave only power connected otherwise, through MagSafe if the Mac has it.",
                "Hold the power button for up to 10 seconds until the Mac turns off.",
                "Press and release power, then immediately hold left Control, left Option, right Shift and power together.",
                "After about 10 seconds, release the three keys and keep holding power for up to 10 more seconds, until the Mac appears here.",
            ]
        case .laptopT2:
            [
                "Plug the cable into the DFU port. Leave only power connected otherwise.",
                "Hold the power button for up to 10 seconds until the Mac turns off.",
                "Press and release power, then immediately hold left Control, left Option, right Shift and power together for about 3 seconds, until the Mac appears here.",
            ]
        case .desktop:
            [
                "Plug the cable into the DFU port, with nothing else in the USB ports.",
                "Unplug the Mac from power, then press and hold its power button.",
                "Keep holding it while you plug the power back in, for up to 10 seconds, until the Mac appears here.",
            ]
        }
    }
}
