import SwiftUI

/// One field's control, picked by its Keystatic type.
struct FieldControl: View {
    @Environment(\.inSettingsForm) private var inSettingsForm
    @Environment(\.guidField) private var guidField
    let spec: FieldSpec
    @Binding var value: FieldValue
    var slug: String?

    var body: some View {
        VStack(alignment: inSettingsForm ? .trailing : .leading, spacing: 4) {
            control
            if let description = spec.description, spec.type != "checkbox", !inSettingsForm {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch spec.type {
        case "slug":
            VStack(alignment: .leading, spacing: 3) {
                TextField(spec.title, text: stringBinding, prompt: Text(Placeholder.text(for: spec)))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                if let slug {
                    Text("\(spec.slug?.label ?? "Address"): \(slug)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        case "text" where spec.key == guidField && !value.isEmpty:
            // Podcast apps track an episode by its guid: set once, never changed.
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption)
                Text(value.string ?? "").font(.callout.monospaced()).textSelection(.enabled)
            }
            .help("Locked: podcast apps track the episode by it")
        case "text", "url":
            TextInput(spec: spec, text: stringBinding)
        case "integer":
            TextField(spec.title, value: intBinding, format: .number.grouping(.never), prompt: Text(Placeholder.text(for: spec)))
                .settingsFieldStyle(inSettingsForm)
                .labelsHidden()
                .frame(maxWidth: 140, alignment: inSettingsForm ? .trailing : .leading)
        case "checkbox":
            HStack(spacing: 10) {
                Toggle(spec.title, isOn: boolBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                if let description = spec.description, !inSettingsForm {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
        case "select":
            SelectField(spec: spec, value: $value)
        case "multiselect" where spec.maxItems == 1:
            SingleChoiceListField(spec: spec, value: $value)
        case "multiselect":
            MultiSelectField(spec: spec, value: $value)
        case "date", "datetime":
            DateField(spec: spec, value: $value)
        case "relationship":
            RelationshipField(spec: spec, value: $value)
        case "array":
            ArrayField(spec: spec, value: $value)
        case "object":
            GroupBox {
                FieldRows(fields: spec.fields ?? [], data: $value)
            }
        case "conditional":
            ConditionalField(spec: spec, value: $value)
        case "file", "image":
            AssetField(spec: spec, value: $value)
        default:
            Text(value.string ?? "None")
                .foregroundStyle(.secondary)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(get: { value.string ?? "" }, set: { value = .string($0) })
    }

    private var intBinding: Binding<Int?> {
        Binding(get: { value.int }, set: { value = $0.map(FieldValue.int) ?? .null })
    }

    private var boolBinding: Binding<Bool> {
        Binding(get: { value.bool ?? false }, set: { value = .bool($0) })
    }
}

/// A text field, growing for multiline ones, with a count when there's a limit.
struct TextInput: View {
    @Environment(\.inSettingsForm) private var inSettingsForm
    let spec: FieldSpec
    @Binding var text: String

    var body: some View {
        VStack(alignment: inSettingsForm ? .trailing : .leading, spacing: 3) {
            if spec.multiline == true {
                TextField(spec.title, text: $text, prompt: Text(Placeholder.text(for: spec)), axis: .vertical)
                    .lineLimit(1...12)
            } else {
                TextField(spec.title, text: $text, prompt: Text(Placeholder.text(for: spec)))
            }
            if let max = spec.maxLength {
                Text("\(text.count) / \(max)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count > max ? .red : .secondary)
            }
        }
        .settingsFieldStyle(inSettingsForm)
        .frame(maxWidth: inSettingsForm ? 340 : .infinity, alignment: inSettingsForm ? .trailing : .leading)
        .labelsHidden()
    }
}

extension View {
    /// Plain in the entry editor, where the form is the page. In a settings
    /// form a borderless value on the right read as fixed text, so it gets
    /// the usual box, with its text from the left like any Mac field.
    @ViewBuilder
    func settingsFieldStyle(_ inSettingsForm: Bool) -> some View {
        if inSettingsForm {
            // The grouped form right-aligns field text unless told otherwise.
            textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
        } else {
            textFieldStyle(.plain)
        }
    }
}

struct SelectField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        let options = spec.options ?? []
        let current = value.string ?? ""
        Picker(spec.title, selection: Binding(get: { current }, set: { value = .string($0) })) {
            if !options.contains(where: { $0.value == current }) {
                Text(current.isEmpty ? "None" : current).tag(current)
            }
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// A list capped at one item, shown as a menu. It still saves as a list
/// (`[posts]`), which is what the site reads.
struct SingleChoiceListField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        let options = spec.options ?? []
        let current = value.array?.first?.string ?? ""
        Picker(spec.title, selection: Binding(
            get: { current },
            set: { value = .array($0.isEmpty ? [] : [.string($0)]) }
        )) {
            if current.isEmpty || !options.contains(where: { $0.value == current }) {
                Text(current.isEmpty ? "None" : current).tag(current)
            }
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Picked options as tokens, with a menu to add the rest.
struct MultiSelectField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    private var picked: [String] { (value.array ?? []).compactMap(\.string) }

    var body: some View {
        let options = spec.options ?? []
        let labels = Dictionary(options.map { ($0.value, $0.label) }, uniquingKeysWith: { a, _ in a })
        FlowLayout(spacing: 6) {
            ForEach(picked, id: \.self) { key in
                Token(text: labels[key] ?? key) {
                    value = .array(picked.filter { $0 != key }.map(FieldValue.string))
                }
            }
            let rest = options.filter { !picked.contains($0.value) }
            if !rest.isEmpty {
                Menu {
                    ForEach(rest, id: \.value) { option in
                        Button(option.label) { value = .array((picked + [option.value]).map(FieldValue.string)) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add \(spec.title.lowercased())")
            }
        }
    }
}

struct Token: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(text)")
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .foregroundStyle(.tint)
        .background(.tint.opacity(0.13), in: Capsule())
    }
}

struct DateField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        if let date = value.date {
            DatePicker(spec.title, selection: Binding(get: { date }, set: { value = .date($0, raw: raw($0)) }),
                       displayedComponents: spec.type == "date" ? [.date] : [.date, .hourAndMinute])
                .labelsHidden()
                .fixedSize()
        } else {
            Button("Add Date") { value = .date(.now, raw: raw(.now)) }
                .buttonStyle(.link)
        }
    }

    /// How Keystatic writes the field: a plain date, or UTC with milliseconds.
    private func raw(_ date: Date) -> String {
        if spec.type == "date" {
            return date.formatted(.iso8601.year().month().day())
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: date)
    }
}

/// A pick from another collection, by its address.
struct RelationshipField: View {
    @Environment(SiteStore.self) private var store
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        let key = spec.collection ?? ""
        let item = store.schema?.item(key)
        let entries = store.entries[key] ?? []
        let current = value.string ?? ""
        Picker(spec.title, selection: Binding(get: { current }, set: { value = $0.isEmpty ? .null : .string($0) })) {
            Text("None").tag("")
            if !current.isEmpty, !entries.contains(where: { $0.slug == current }) {
                Text(current).tag(current)
            }
            ForEach(entries) { entry in
                Text(item.map { SiteStore.title(of: entry, item: $0) } ?? entry.slug).tag(entry.slug)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 360, alignment: .leading)
    }
}

/// A list of one kind of field, with add and remove.
struct ArrayField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        let count = value.array?.count ?? 0
        list(count)
            .environment(\.fieldPath, nil)
    }

    private func list(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let element = spec.element {
                ForEach(0..<count, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if element.type == "object" {
                            GroupBox {
                                FieldRows(fields: element.fields ?? [], data: $value.item(index))
                            }
                        } else {
                            FieldControl(spec: element, value: $value.item(index))
                        }
                        Button {
                            guard var list = value.array, list.indices.contains(index) else { return }
                            list.remove(at: index)
                            value = .array(list)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove")
                    }
                }
                Button {
                    value = .array((value.array ?? []) + [Defaults.value(for: element)])
                } label: {
                    Label("Add \(element.label ?? "Item")", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// A menu that swaps the fields under it (Keystatic's conditional).
struct ConditionalField: View {
    let spec: FieldSpec
    @Binding var value: FieldValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let discriminant = spec.discriminant {
                FieldControl(spec: discriminant, value: $value.child("discriminant"))
                let picked = value["discriminant"]?.string ?? ""
                if let sub = spec.values?.first(where: { $0.key == picked }) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(sub.title).foregroundStyle(.secondary)
                        FieldControl(spec: sub, value: $value.child("value"))
                    }
                }
            }
        }
        .environment(\.fieldPath, nil)
    }
}

/// What an empty field says. The field's own label read as a value
/// ("Description" in the Description field), so say whether it's needed.
enum Placeholder {
    static func text(for spec: FieldSpec) -> String {
        let required = spec.validation?.isRequired == true || (spec.validation?.length?.min ?? 0) > 0
        return required ? "Required" : "Optional"
    }
}

/// The value a new item starts with.
enum Defaults {
    static func value(for spec: FieldSpec) -> FieldValue {
        switch spec.type {
        case "object":
            return .object((spec.fields ?? []).map { FieldPair(key: $0.key, value: value(for: $0)) })
        case "array", "multiselect":
            return .array([])
        case "checkbox":
            return .bool(false)
        case "select":
            return spec.options?.first.map { .string($0.value) } ?? .null
        case "text", "slug", "url":
            return .string("")
        case "conditional":
            let first = spec.discriminant?.options?.first?.value ?? ""
            let sub = spec.values?.first { $0.key == first }
            return .object([FieldPair(key: "discriminant", value: .string(first)),
                            FieldPair(key: "value", value: sub.map(value(for:)) ?? .null)])
        default:
            return .null
        }
    }
}

/// Wraps children onto new lines, like tokens in Mail's address field.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

extension EnvironmentValues {
    /// An episode's guid field, which locks once set. Nil outside podcasts.
    @Entry var guidField: String?
}
