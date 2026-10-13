import Foundation

/// The site's Keystatic config, as `scripts/schema-dump.mjs` prints it.
struct SiteSchema: Decodable, Sendable {
    struct Group: Decodable, Sendable, Identifiable {
        let name: String
        let keys: [String]
        var id: String { name }
    }

    let navigation: [Group]?
    let items: [SchemaItem]

    func item(_ key: String) -> SchemaItem? {
        items.first { $0.key == key }
    }

    /// Sidebar groups in the config's order. Anything the config leaves out
    /// of its navigation lands in a last "Other" group, so nothing is hidden.
    var groups: [(name: String, items: [SchemaItem])] {
        guard let navigation else { return [("Content", items)] }
        var listed = Set<String>()
        var result: [(name: String, items: [SchemaItem])] = navigation.map { group in
            listed.formUnion(group.keys)
            return (group.name, group.keys.compactMap(item))
        }
        let rest = items.filter { !listed.contains($0.key) }
        if !rest.isEmpty { result.append(("Other", rest)) }
        return result
    }
}

/// One collection (a folder of entries) or singleton (one file).
struct SchemaItem: Decodable, Sendable, Identifiable, Hashable {
    enum Kind: String, Decodable, Sendable {
        case collection, singleton
    }

    let key: String
    let kind: Kind
    let label: String
    let path: String
    let format: Format
    let slugField: String?
    let previewUrl: String?
    let fields: [FieldSpec]

    var id: String { key }

    static func == (a: SchemaItem, b: SchemaItem) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    /// The body field (markdoc), if entries have one.
    var bodyField: FieldSpec? {
        guard let name = format.contentField else { return nil }
        return fields.first { $0.key == name }
    }

    /// The fields that live in the frontmatter or data file.
    var dataFields: [FieldSpec] {
        fields.filter { $0.key != format.contentField && $0.type != "ignored" }
    }

    /// File extension: `md` for entries with a body, else the data format.
    var fileExtension: String {
        if format.contentField != nil { return bodyField?.extensionName ?? "mdoc" }
        return format.data == "json" ? "json" : "yaml"
    }

    /// The first date field, used to sort the list newest first.
    var dateField: FieldSpec? {
        dataFields.first { $0.type == "date" || $0.type == "datetime" }
    }

    /// A dated stream of short text entries with no body: asides.
    var isStream: Bool {
        format.contentField == nil && dateField != nil && textField != nil
    }

    /// The folder a collection's entries live in (src/content/asides).
    var folder: String {
        path.replacingOccurrences(of: "/**", with: "").replacingOccurrences(of: "/*", with: "")
    }

    /// The first multiline text field: an aside's text, a work's blurb.
    var textField: FieldSpec? {
        dataFields.first { $0.type == "text" && $0.multiline == true }
    }

    /// What names an entry in the list. A stream entry reads better by its
    /// text than by its file name; anything else goes by its title.
    var titleField: FieldSpec? {
        if isStream, let text = textField { return text }
        if let slugField, let field = dataFields.first(where: { $0.key == slugField }) { return field }
        return dataFields.first { $0.type == "text" || $0.type == "slug" }
    }
}

/// Keystatic's `format`: a string ("yaml") or an object with `data` and
/// `contentField`.
struct Format: Decodable, Sendable {
    var data = "yaml"
    var contentField: String?

    init(data: String = "yaml", contentField: String? = nil) {
        self.data = data
        self.contentField = contentField
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            data = name
            return
        }
        struct Object: Decodable {
            let data: String?
            let contentField: String?
        }
        let object = try container.decode(Object.self)
        data = object.data ?? "yaml"
        contentField = object.contentField
    }
}

/// One field and its settings. Containers (object, array, conditional) hold
/// their child fields.
final class FieldSpec: Decodable, Sendable, Identifiable {
    struct Option: Decodable, Sendable, Hashable {
        let label: String
        let value: String
    }

    struct Validation: Decodable, Sendable {
        struct Length: Decodable, Sendable {
            let min: Int?
            let max: Int?
        }
        let isRequired: Bool?
        let length: Length?
        let min: Double?
        let max: Double?
    }

    struct SubLabel: Decodable, Sendable {
        let label: String?
        let description: String?
    }

    let key: String
    let type: String
    let label: String?
    let description: String?
    let multiline: Bool?
    let options: [Option]?
    let validation: Validation?
    let fields: [FieldSpec]?
    let element: FieldSpec?
    let discriminant: FieldSpec?
    let values: [FieldSpec]?
    let collection: String?
    let extensionName: String?
    /// Where an image or file field keeps its files, and what goes before
    /// the file name in the entry (see AssetPlace).
    let directory: String?
    let publicPath: String?
    let slug: SubLabel?
    /// A list's cap from the site's Astro schema (a post has one kind).
    let maxItems: Int?
    /// The default when it's a plain string (a select's "en").
    let defaultString: String?
    /// The config's other defaults: a list's (a post's kind), a number's
    /// (chapter 1), a switch's, and a date's "now" or "today".
    let defaultStrings: [String]?
    let defaultInt: Int?
    let defaultBool: Bool?
    let defaultKind: String?

    var id: String { key }
    /// Keystatic's conditional has no label of its own; its menu has one.
    var title: String { label ?? discriminant?.label ?? key }

    enum CodingKeys: String, CodingKey {
        case key, type, label, description, multiline, options, validation, fields, element
        case discriminant, values, collection, slug, maxItems, defaultValue, directory, publicPath
        case extensionName = "extension"
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        type = try c.decode(String.self, forKey: .type)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        multiline = try c.decodeIfPresent(Bool.self, forKey: .multiline)
        // Options can be a list (select) or something else on other fields
        // (markdoc's editor options). Only the list form matters here.
        options = try? c.decodeIfPresent([Option].self, forKey: .options)
        validation = try? c.decodeIfPresent(Validation.self, forKey: .validation)
        fields = try c.decodeIfPresent([FieldSpec].self, forKey: .fields)
        element = try c.decodeIfPresent(FieldSpec.self, forKey: .element)
        discriminant = try c.decodeIfPresent(FieldSpec.self, forKey: .discriminant)
        values = try c.decodeIfPresent([FieldSpec].self, forKey: .values)
        collection = try c.decodeIfPresent(String.self, forKey: .collection)
        extensionName = try c.decodeIfPresent(String.self, forKey: .extensionName)
        directory = try? c.decodeIfPresent(String.self, forKey: .directory)
        publicPath = try? c.decodeIfPresent(String.self, forKey: .publicPath)
        slug = try? c.decodeIfPresent(SubLabel.self, forKey: .slug)
        maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems)
        defaultString = try? c.decodeIfPresent(String.self, forKey: .defaultValue)
        defaultStrings = try? c.decodeIfPresent([String].self, forKey: .defaultValue)
        defaultInt = try? c.decodeIfPresent(Int.self, forKey: .defaultValue)
        defaultBool = try? c.decodeIfPresent(Bool.self, forKey: .defaultValue)
        struct Kind: Decodable { let kind: String }
        defaultKind = (try? c.decodeIfPresent(Kind.self, forKey: .defaultValue))?.kind
    }

    var maxLength: Int? { validation?.length?.max }

    /// An image or file field: its value names a file in the repo.
    var isAsset: Bool { type == "image" || type == "file" }
}
