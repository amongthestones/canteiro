import SwiftUI
import UniformTypeIdentifiers

/// A collection: its entries on the left, the selected one on the right.
struct CollectionView: View {
    @Environment(SiteStore.self) private var store
    let item: SchemaItem
    @State private var search = ""
    @AppStorage("listWidth") private var listWidth = 320.0
    @State private var dropTargeted = false
    @State private var filter = ListFilter()

    private var entries: [Entry] {
        let all = (store.entries[item.key] ?? []).filter(filter.matches)
        guard !search.isEmpty else { return all }
        return all.filter { SiteStore.title(of: $0, item: item).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        @Bindable var store = store
        // The list keeps the width you drag it to, like Mail's. (HSplitView
        // sized it from its largest allowed width and squeezed the sidebar.)
        HStack(spacing: 0) {
            List(selection: $store.selectedEntry[item.key]) {
                if store.isEpisodes(item) {
                    EpisodeDropHint(targeted: dropTargeted)
                }
                ForEach(entries) { entry in
                    EntryRow(entry: entry, item: item).tag(entry.id)
                }
            }
            .contextMenu(forSelectionType: Entry.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Move to Trash", systemImage: "trash", role: .destructive) {
                        store.trash(item, ids: ids)
                    }
                }
            }
            // The Delete key and Edit › Delete, as in Mail and Notes.
            .onDeleteCommand {
                if let id = store.selectedEntry[item.key] { store.trash(item, ids: [id]) }
            }
            .frame(width: listWidth)
            .dropDestination(for: URL.self) { urls, _ in
                let audio = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) == true }
                guard store.isEpisodes(item), !audio.isEmpty else { return false }
                for file in audio { Task { await store.createEpisode(item, from: file) } }
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(search.isEmpty && !filter.isActive ? "No Entries" : "No Matches", systemImage: SidebarView.icon(for: item))
                }
            }

            ResizeHandle(width: $listWidth, range: 240...440)

            Group {
                if let id = store.selectedEntry[item.key], let entry = store.entries[item.key]?.first(where: { $0.id == id }) {
                    EntryEditor(item: item, entry: entry)
                        .id("\(entry.id)#\(store.revisions[entry.id] ?? 0)")
                } else {
                    ContentUnavailableView("No Entry Selected", systemImage: SidebarView.icon(for: item))
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSubtitle(filter.isActive
            ? "\(item.label) · \(entries.count) of \(store.entries[item.key]?.count ?? 0)"
            : "\(item.label) · \(store.entries[item.key]?.count ?? 0)")
        .toolbar {
            ToolbarItem(placement: .navigation) { NewEntryButton() }
            if ListFilterMenu.applies(to: item) {
                ToolbarItem(placement: .navigation) { ListFilterMenu(item: item, filter: $filter) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search \(item.label)")
        .onAppear {
            if store.selectedEntry[item.key] == nil { store.selectedEntry[item.key] = entries.first?.id }
        }
    }
}

/// The top of an episode list: where an MP3 goes.
struct EpisodeDropHint: View {
    let targeted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").font(.title3).foregroundStyle(.tint)
            Text("Drop an MP3 here for a new episode. It goes up to R2, and the length, number and guid fill in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)))
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
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
        // No body: a text field such as a work's blurb says more than the
        // file name. A stream's text is already the title.
        if !item.isStream, let field = item.textField, let text = entry.data[field.key]?.string, !text.isEmpty {
            return text
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
                // Always two lines tall, like Mail: the list caches row
                // heights, so a line that grows while you type got cut in half.
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
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
                SingletonEditor(item: item, entry: entry)
                    .id("\(entry.id)#\(store.revisions[entry.id] ?? 0)")
            } else {
                ContentUnavailableView("Not Made Yet", systemImage: "doc.badge.plus",
                                       description: Text("\(item.path).\(item.fileExtension) doesn't exist yet."))
            }
        }
        .navigationSubtitle(item.label)
    }
}

/// A singleton's settings. Edits save themselves (see Autosave).
struct SingletonEditor: View {
    @Environment(SiteStore.self) private var store
    let item: SchemaItem
    let entry: Entry
    @State private var data: FieldValue

    init(item: SchemaItem, entry: Entry) {
        self.item = item
        self.entry = entry
        _data = State(initialValue: entry.data)
    }

    var body: some View {
        SettingsForm(fields: item.dataFields, data: $data)
            .autosave(item, id: entry.id, data: data, body: nil)
            .environment(\.assetPlace, store.siteURL.map { AssetPlace(site: $0, item: item, slug: nil) })
    }
}

/// A divider you can drag, with the column-resize pointer, like the edge
/// between Mail's list and message.
struct ResizeHandle: View {
    enum Side { case right, left }

    @Binding var width: Double
    let range: ClosedRange<Double>
    /// Which way dragging widens the column: a column left of the handle
    /// grows as you drag right, one right of it as you drag left.
    var grows: Side = .right
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
                                let delta = grows == .right ? drag.translation.width : -drag.translation.width
                                width = min(max(from + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}
