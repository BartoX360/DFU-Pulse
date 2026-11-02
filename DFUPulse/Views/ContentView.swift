import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case flash, library, guide

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .flash: "Flash"
        case .library: "Library"
        case .guide: "Port guide"
        }
    }

    var symbol: String {
        switch self {
        case .flash: "bolt.fill"
        case .library: "externaldrive.fill"
        case .guide: "cable.connector"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppSection = .flash

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image("Logo").resizable().frame(width: 34, height: 34)
                    Text(verbatim: "DFU Pulse").font(.title3.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ZStack {
                PulseBackground()
                switch selection {
                case .flash: FlashView(showGuide: { selection = .guide })
                case .library: LibraryView()
                case .guide: GuideView()
                }
            }
        }
    }
}
