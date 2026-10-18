import SwiftUI

/// The list's order. The standard order is the collection's own (newest by
/// its date field, by order number, or by title); the others read the file:
/// when it was last saved, or when it was made.
enum ListSort: String, CaseIterable {
    case standard
    case edited
    case added
    case title

    func label(for item: SchemaItem) -> String {
        switch self {
        case .standard: return item.dateField?.title ?? (Self.hasOrder(item) ? "Order" : "Title")
        case .edited: return "Last Edited"
        case .added: return "Date Added"
        case .title: return "Title"
        }
    }

    /// Title is offered only when the standard order isn't already by title.
    static func options(for item: SchemaItem) -> [ListSort] {
        let byTitle = item.dateField == nil && !hasOrder(item)
        return allCases.filter { !(byTitle && $0 == .title) }
    }

    /// The store keeps each list in the standard order, so that one needs no work.
    func apply(_ list: [Entry], item: SchemaItem) -> [Entry] {
        switch self {
        case .standard:
            return list
        case .edited, .added:
            let dates = Dictionary(uniqueKeysWithValues: list.map { ($0.id, fileDate($0) ?? .distantPast) })
            return list.sorted { dates[$0.id]! > dates[$1.id]! }
        case .title:
            return list.sorted { SiteStore.title(of: $0, item: item).localizedStandardCompare(SiteStore.title(of: $1, item: item)) == .orderedAscending }
        }
    }

    /// The file date this order goes by, for the row to show.
    func fileDate(_ entry: Entry) -> Date? {
        let key: URLResourceKey
        switch self {
        case .edited: key = .contentModificationDateKey
        case .added: key = .creationDateKey
        default: return nil
        }
        let values = try? entry.url.resourceValues(forKeys: [key])
        return self == .edited ? values?.contentModificationDate : values?.creationDate
    }

    private static func hasOrder(_ item: SchemaItem) -> Bool {
        item.dataFields.contains { $0.type == "integer" }
    }
}

/// The sort button over the list, beside Filter.
struct ListSortMenu: View {
    let item: SchemaItem
    @Binding var sort: ListSort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(ListSort.options(for: item), id: \.self) { Text($0.label(for: item)) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort the list")
    }
}
