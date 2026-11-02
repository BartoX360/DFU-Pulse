import SwiftUI

/// The Macs a release can be installed on, grouped by product line, so a
/// version is checked before 20 GB are downloaded for nothing.
struct CompatibilityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let release: Firmware
    @State private var query = ""

    private struct Mac: Identifiable {
        let id: String
        let name: String
        var line: String { String(name.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces) }
    }

    private var groups: [(String, [Mac])] {
        let macs = release.models
            .map { Mac(id: $0, name: model.catalog.displayName(for: $0)) }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.id.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Dictionary(grouping: macs, by: \.line)
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { line, macs in
                    Section(line) {
                        ForEach(macs) { mac in
                            LabeledContent {
                                Text(verbatim: mac.id).monospaced().foregroundStyle(.secondary)
                            } label: {
                                Text(verbatim: mac.name)
                            }
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .toolbar)
            .navigationTitle(Text(verbatim: "macOS \(release.version) (\(release.build))"))
            .navigationSubtitle(Text("Compatible with \(release.models.count) Mac models"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }
}
