import SwiftUI

/// A singleton laid out like System Settings: a grouped form with one
/// section per group of fields. Nested groups become their own sections
/// rather than boxes inside boxes.
struct SettingsForm: View {
    let fields: [FieldSpec]
    @Binding var data: FieldValue

    var body: some View {
        Form {
            let simple = fields.filter { !Self.isContainer($0) }
            if !simple.isEmpty {
                Section {
                    ForEach(simple) { field in
                        SettingsRow(spec: field, value: $data.child(field.key))
                    }
                }
            }
            ForEach(fields.filter(Self.isContainer)) { field in
                SettingsSections(spec: field, value: $data.child(field.key), trail: [])
            }
        }
        .formStyle(.grouped)
        .environment(\.inSettingsForm, true)
    }

    static func isContainer(_ field: FieldSpec) -> Bool {
        field.type == "object" || (field.type == "array" && field.element != nil)
    }
}

/// The sections for one group: its plain fields in one section, then a
/// section for each group inside it, titled with the path to it.
private struct SettingsSections: View {
    let spec: FieldSpec
    @Binding var value: FieldValue
    let trail: [String]

    private var title: String { (trail + [spec.title]).joined(separator: " › ") }

    var body: some View {
        switch spec.type {
        case "object":
            let children = spec.fields ?? []
            let simple = children.filter { !SettingsForm.isContainer($0) }
            if !simple.isEmpty {
                Section {
                    ForEach(simple) { child in
                        SettingsRow(spec: child, value: $value.child(child.key))
                    }
                } header: {
                    SectionHeader(title: title, description: spec.description)
                }
            }
            ForEach(children.filter(SettingsForm.isContainer)) { child in
                SettingsSections(spec: child, value: $value.child(child.key), trail: trail + [spec.title])
            }
        case "array":
            SettingsList(spec: spec, value: $value, title: title)
        default:
            EmptyView()
        }
    }
}

/// A list field: one section per item when items are groups (each glossary
/// term), else one section of rows (each tag).
private struct SettingsList: View {
    let spec: FieldSpec
    @Binding var value: FieldValue
    let title: String

    var body: some View {
        let element = spec.element!
        let count = value.array?.count ?? 0
        if element.type == "object" {
            // A footer under each item broke the first item's box, so
            // Remove is a row inside it. The list's title heads the first
            // item, or the Add button when the list is empty.
            ForEach(0..<count, id: \.self) { index in
                if index == 0 {
                    Section {
                        itemRows(element, index)
                        removeRow(index)
                    } header: {
                        SectionHeader(title: title, description: spec.description)
                    }
                } else {
                    Section {
                        itemRows(element, index)
                        removeRow(index)
                    }
                }
            }
            if count == 0 {
                Section {
                    addButton(element)
                } header: {
                    SectionHeader(title: title, description: spec.description)
                }
            } else {
                Section {
                    addButton(element)
                }
            }
        } else {
            Section {
                ForEach(0..<count, id: \.self) { index in
                    HStack {
                        FieldControl(spec: element, value: $value.item(index))
                        Spacer()
                        Button { remove(index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove")
                    }
                }
                addButton(element)
            } header: {
                SectionHeader(title: title, description: spec.description)
            }
        }
    }

    private func itemRows(_ element: FieldSpec, _ index: Int) -> some View {
        ForEach(element.fields ?? []) { child in
            SettingsRow(spec: child, value: $value.item(index).child(child.key))
        }
    }

    private func removeRow(_ index: Int) -> some View {
        HStack {
            Spacer()
            Button("Remove", role: .destructive) { remove(index) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private func addButton(_ element: FieldSpec) -> some View {
        Button {
            value = .array((value.array ?? []) + [Defaults.value(for: element)])
        } label: {
            Label("Add \(element.label ?? "Item")", systemImage: "plus")
        }
        .buttonStyle(.borderless)
    }

    private func remove(_ index: Int) {
        guard var list = value.array, list.indices.contains(index) else { return }
        list.remove(at: index)
        value = .array(list)
    }
}

/// One row: the label and its help text on the left, the control on the right.
struct SettingsRow: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        LabeledContent {
            FieldControl(spec: spec, value: $value)
        } label: {
            Text(spec.title)
            if let description = spec.description {
                Text(description)
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

extension EnvironmentValues {
    /// In a settings form the label column shows each field's help text, and
    /// values sit on the right.
    @Entry var inSettingsForm = false
}
