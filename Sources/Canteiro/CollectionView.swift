import SwiftUI

/// A collection: its entries on the left, the selected one on the right.
struct CollectionView: View {
    @Environment(SiteStore.self) private var store
    let item: SchemaItem
    @State private var search = ""
    @AppStorage("listWidth") private var listWidth = 320.0

    private var entries: [Entry] {
        let all = store.entries[item.key] ?? []
        guard !search.isEmpty else { return all }
        return all.filter { SiteStore.title(of: $0, item: item).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        @Bindable var store = store
        // The list keeps the width you drag it to, like Mail's. (HSplitView
        // sized it from its largest allowed width and squeezed the sidebar.)
        HStack(spacing: 0) {
            List(selection: $store.selectedEntry[item.key]) {
                ForEach(entries) { entry in
                    EntryRow(entry: entry, item: item).tag(entry.id)
                }
            }
            .frame(width: listWidth)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No Entries" : "No Matches", systemImage: SidebarView.icon(for: item))
                }
            }

            ResizeHandle(width: $listWidth, range: 240...520)

            Group {
                if let id = store.selectedEntry[item.key], let entry = store.entries[item.key]?.first(where: { $0.id == id }) {
                    EntryEditor(item: item, entry: entry).id(entry.id)
                } else {
                    ContentUnavailableView("No Entry Selected", systemImage: SidebarView.icon(for: item))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSubtitle("\(item.label) · \(store.entries[item.key]?.count ?? 0)")
        .searchable(text: $search, placement: .toolbar, prompt: "Search \(item.label)")
        .onAppear {
            if store.selectedEntry[item.key] == nil { store.selectedEntry[item.key] = entries.first?.id }
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let item: SchemaItem

    private var isDraft: Bool { entry.data["draft"]?.bool == true }

    private var dateText: String? {
        guard let field = item.dateField, let date = entry.data[field.key]?.date else { return nil }
        let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(thisYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }

    private var subtitle: String {
        if let body = entry.body {
            let line = body.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("![") && !$0.hasPrefix("#") }
            return line.map(String.init) ?? entry.slug
        }
        return entry.slug
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(isDraft ? Color.orange : .clear)
                .frame(width: 7, height: 7)
                .accessibilityLabel(isDraft ? "Draft" : "")
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SiteStore.title(of: entry, item: item))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let dateText {
                        Text(dateText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

/// A singleton fills the whole space: no list, just its form.
struct SingletonView: View {
    @Environment(SiteStore.self) private var store
    let item: SchemaItem

    var body: some View {
        Group {
            if let entry = store.singletons[item.key] {
                EntryEditor(item: item, entry: entry)
            } else {
                ContentUnavailableView("Not Made Yet", systemImage: "doc.badge.plus",
                                       description: Text("\(item.path).\(item.fileExtension) doesn't exist yet."))
            }
        }
        .navigationSubtitle(item.label)
    }
}

/// A divider you can drag, with the column-resize pointer, like the edge
/// between Mail's list and message.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var start: Double?

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let from = start ?? width
                                start = from
                                width = min(max(from + drag.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}
