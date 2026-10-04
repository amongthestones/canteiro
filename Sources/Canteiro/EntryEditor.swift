import SwiftUI

/// One entry's form, built from its schema, with the body under it.
/// Edits stay in memory for now: saving comes next.
struct EntryEditor: View {
    let item: SchemaItem
    let entry: Entry
    @State private var data: FieldValue
    @State private var text: String
    @State private var showMore = false

    init(item: SchemaItem, entry: Entry) {
        self.item = item
        self.entry = entry
        _data = State(initialValue: entry.data)
        _text = State(initialValue: entry.body ?? "")
    }

    /// Fields worth seeing at once: required ones, ones with a value, and
    /// switches and menus. Empty optional fields fold under "More fields".
    /// Decided from the file as opened, so a field doesn't jump away when
    /// it's cleared.
    private var split: (main: [FieldSpec], more: [FieldSpec]) {
        let fields = item.dataFields
        guard item.kind == .collection else { return (fields, []) }
        let main = fields.filter { field in
            field.validation?.isRequired == true
                || (field.validation?.length?.min ?? 0) > 0
                || ["slug", "checkbox", "select"].contains(field.type)
                || !(entry.data[field.key]?.isEmpty ?? true)
        }
        let mainKeys = Set(main.map(\.key))
        return (main, fields.filter { !mainKeys.contains($0.key) })
    }

    private var isEdited: Bool { data != entry.data || text != (entry.body ?? "") }

    var body: some View {
        let split = split
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FieldRows(fields: split.main, data: $data, slug: entry.slug)
                if !split.more.isEmpty {
                    DisclosureGroup(isExpanded: $showMore) {
                        FieldRows(fields: split.more, data: $data, slug: entry.slug)
                    } label: {
                        Text("More fields")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
                if item.bodyField != nil {
                    BodyTextView(text: $text)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            if isEdited {
                ToolbarItem {
                    Label("Edited", systemImage: "pencil.circle")
                        .help("Edited here. Saving isn't in this version yet.")
                }
            }
        }
    }
}

/// Label on the left, control on the right, a hairline between rows: the
/// header of a Mail message.
struct FieldRows: View {
    let fields: [FieldSpec]
    @Binding var data: FieldValue
    var slug: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(fields) { field in
                GridRow {
                    Text(field.title)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 96, alignment: .leading)
                    FieldControl(spec: field, value: $data.child(field.key), slug: slug)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }
}

extension Binding where Value == FieldValue {
    func child(_ key: String) -> Binding<FieldValue> {
        Binding(
            get: { wrappedValue[key] ?? .null },
            set: { wrappedValue[key] = $0 }
        )
    }

    func item(_ index: Int) -> Binding<FieldValue> {
        Binding(
            get: {
                guard let list = wrappedValue.array, list.indices.contains(index) else { return .null }
                return list[index]
            },
            set: {
                guard var list = wrappedValue.array, list.indices.contains(index) else { return }
                list[index] = $0
                wrappedValue = .array(list)
            }
        )
    }
}
