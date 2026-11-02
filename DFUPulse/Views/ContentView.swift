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
        case .flash: "bolt"
        case .library: "externaldrive"
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection {
            case .flash: FlashView(showGuide: { selection = .guide })
            case .library: LibraryView()
            case .guide: GuideView()
            }
        }
    }
}
