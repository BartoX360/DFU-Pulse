import Foundation

/// Where the DFU port sits, from Apple's "How to identify the DFU port on Mac".
struct PortFamily: Identifiable, Hashable, Sendable {
    enum Position: Sendable { case first, middle, last }
    enum Kind: Sendable { case laptop, laptopT2, desktop }

    let id: String
    let product: String
    let detail: LocalizedStringResource
    let symbol: String
    let kind: Kind
    let position: Position
    /// USB-C ports on the face that holds the DFU port; nil when it varies by model.
    let ports: Int?
    /// Replaces the diagram when the port is not on a row (Mac Pro).
    var note: LocalizedStringResource? = nil

    static func == (lhs: PortFamily, rhs: PortFamily) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PortFamily {
    // Every Mac laptop has exactly two USB-C ports on its left side.
    static let all: [PortFamily] = [
        .init(id: "neo", product: "MacBook Neo", detail: "All models",
              symbol: "macbook", kind: .laptop, position: .first, ports: 2),
        .init(id: "mba-2025", product: "MacBook Air", detail: "Apple silicon, 2025 or later",
              symbol: "macbook", kind: .laptop, position: .last, ports: 2),
        .init(id: "mba-as", product: "MacBook Air", detail: "Earlier Apple silicon models",
              symbol: "macbook", kind: .laptop, position: .first, ports: 2),
        .init(id: "mba-t2", product: "MacBook Air", detail: "Intel with T2 chip",
              symbol: "macbook", kind: .laptopT2, position: .last, ports: 2),
        .init(id: "mbp-base", product: "MacBook Pro", detail: "14-inch M4 or M5 (not Pro or Max)",
              symbol: "macbook", kind: .laptop, position: .last, ports: 2),
        .init(id: "mbp-as", product: "MacBook Pro", detail: "Other Apple silicon models",
              symbol: "macbook", kind: .laptop, position: .first, ports: 2),
        .init(id: "mbp-t2", product: "MacBook Pro", detail: "Intel with T2 chip",
              symbol: "macbook", kind: .laptopT2, position: .last, ports: 2),
        .init(id: "imac", product: "iMac", detail: "All models",
              symbol: "desktopcomputer", kind: .desktop, position: .last, ports: nil),
        .init(id: "mini-2025", product: "Mac mini", detail: "Apple silicon, 2025 or later",
              symbol: "macmini", kind: .desktop, position: .middle, ports: 3),
        .init(id: "mini-as", product: "Mac mini", detail: "Earlier Apple silicon models",
              symbol: "macmini", kind: .desktop, position: .first, ports: nil),
        .init(id: "mini-t2", product: "Mac mini", detail: "Intel with T2 chip",
              symbol: "macmini", kind: .desktop, position: .last, ports: 4),
        .init(id: "studio", product: "Mac Studio", detail: "All models",
              symbol: "macstudio", kind: .desktop, position: .last, ports: 4),
        .init(id: "pro-tower", product: "Mac Pro", detail: "Tower enclosure",
              symbol: "macpro.gen3", kind: .desktop, position: .last, ports: nil,
              note: "On top, the USB-C port farthest from the power button."),
        .init(id: "pro-rack", product: "Mac Pro", detail: "Rack enclosure",
              symbol: "macpro.gen3", kind: .desktop, position: .first, ports: nil,
              note: "On the front, the USB-C port closest to the power button."),
    ]

    static var products: [String] {
        all.map(\.product).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var isLaptop: Bool { kind != .desktop }

    /// Laptops are seen from their left side, where the hinge is on the left.
    var location: LocalizedStringResource {
        if let note { return note }
        switch (isLaptop, position) {
        case (true, .first): return "Left side: the USB-C port closest to the hinge."
        case (true, _): return "Left side: the USB-C port closest to the front."
        case (false, .first): return "Back: the leftmost USB-C port, seen from behind."
        case (false, .middle): return "Back: the middle USB-C port, seen from behind."
        case (false, .last): return "Back: the rightmost USB-C port, seen from behind."
        }
    }

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

/// How an iPhone or iPad enters DFU, from Apple's service documentation.
/// These devices have no DFU port: any cable to this Mac works, and only
/// their buttons can put them in DFU.
struct MobileFamily: Identifiable, Hashable, Sendable {
    let id: String
    let product: String
    let detail: LocalizedStringResource
    let symbol: String
    let steps: [LocalizedStringResource]

    static func == (lhs: MobileFamily, rhs: MobileFamily) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension MobileFamily {
    static let all: [MobileFamily] = [
        .init(id: "iphone-8", product: "iPhone", detail: "iPhone 8 or later, and iPhone SE (2nd generation or later)",
              symbol: "iphone", steps: [
                  "Press and release volume up, then volume down.",
                  "Hold the side button until the screen turns black.",
                  "Keep holding the side button and also hold volume down for 5 seconds.",
                  "Release the side button and keep holding volume down for about 10 seconds, until the iPhone appears in Flash.",
              ]),
        .init(id: "iphone-7", product: "iPhone", detail: "iPhone 7 and iPhone 7 Plus",
              symbol: "iphone.homebutton", steps: [
                  "Hold the side button and volume down together for 8 seconds.",
                  "Release the side button and keep holding volume down for about 10 seconds, until the iPhone appears in Flash.",
              ]),
        .init(id: "iphone-6s", product: "iPhone", detail: "iPhone 6s or earlier, and iPhone SE (1st generation)",
              symbol: "iphone.homebutton", steps: [
                  "Hold the Home button and the side or top button together for 8 seconds.",
                  "Release the side or top button and keep holding Home for about 10 seconds, until the iPhone appears in Flash.",
              ]),
        .init(id: "ipad-faceid", product: "iPad", detail: "Without a Home button",
              symbol: "ipad", steps: [
                  "Press and release the volume button nearest the top button, then the other volume button.",
                  "Hold the top button until the screen turns black.",
                  "Keep holding the top button and also hold the volume button farthest from it for 5 seconds.",
                  "Release the top button and keep holding the volume button for about 10 seconds, until the iPad appears in Flash.",
              ]),
        .init(id: "ipad-home", product: "iPad", detail: "With a Home button",
              symbol: "ipad.homebutton", steps: [
                  "Hold the Home button and the top button together for 8 seconds.",
                  "Release the top button and keep holding Home for about 10 seconds, until the iPad appears in Flash.",
              ]),
    ]
}
