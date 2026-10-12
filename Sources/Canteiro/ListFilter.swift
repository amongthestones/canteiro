import SwiftUI

/// What the list shows: drafts or published entries, and one option per
/// choice field (a post's kind, its language, a project's status).
struct ListFilter: Equatable {
    enum Status: String, CaseIterable {
        case all = "All"
        case drafts = "Drafts"
        case published = "Published"
    }

    var status = Status.all
    /// Field key → the option value picked. A missing key means any.
    var choices: [String: String] = [:]

    var isActive: Bool { status != .all || !choices.isEmpty }

    func matches(_ entry: Entry) -> Bool {
        let draft = entry.data["draft"]?.bool == true
        if status == .drafts && !draft { return false }
        if status == .published && draft { return false }
        for (key, picked) in choices {
            switch entry.data[key] {
            case .string(let value)?: if value != picked { return false }
            case .array(let values)?: if !values.contains(.string(picked)) { return false }
            default: return false
            }
        }
        return true
    }

    /// Fields the menu offers: selects and multiselects with their options.
    static func choiceFields(of item: SchemaItem) -> [FieldSpec] {
        item.dataFields.filter { ($0.type == "select" || $0.type == "multiselect") && !($0.options ?? []).isEmpty }
    }

    static func hasStatus(_ item: SchemaItem) -> Bool {
        item.dataFields.contains { $0.key == "draft" }
    }
}

/// The filter button over the list. Filled while a filter is on.
struct ListFilterMenu: View {
    let item: SchemaItem
    @Binding var filter: ListFilter

    var body: some View {
        Menu {
            if ListFilter.hasStatus(item) {
                Picker("Status", selection: $filter.status) {
                    ForEach(ListFilter.Status.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.inline)
            }
            ForEach(ListFilter.choiceFields(of: item)) { field in
                Picker(field.title, selection: choice(field.key)) {
                    Text("Any").tag(String?.none)
                    ForEach(field.options ?? [], id: \.self) { Text($0.label).tag(String?.some($0.value)) }
                }
                .pickerStyle(.menu)
            }
            if filter.isActive {
                Divider()
                Button("Show All") { filter = ListFilter() }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .help("Filter the list")
    }

    private func choice(_ key: String) -> Binding<String?> {
        Binding(get: { filter.choices[key] }, set: { filter.choices[key] = $0 })
    }

    /// Only lists with something to filter by get the button.
    static func applies(to item: SchemaItem) -> Bool {
        ListFilter.hasStatus(item) || !ListFilter.choiceFields(of: item).isEmpty
    }
}
