import AppKit
import Foundation
import Observation

/// The open site: its schema and every entry, read once on open.
@MainActor
@Observable
final class SiteStore {
    enum Phase: Equatable {
        case noSite
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .noSite
    private(set) var siteURL: URL?
    private(set) var schema: SiteSchema?
    private(set) var entries: [String: [Entry]] = [:]
    private(set) var singletons: [String: Entry] = [:]
    /// Files that didn't parse. Shown, not hidden: a broken file is worth knowing about.
    private(set) var problems: [String] = []

    /// Entries whose file changed on disk since they were read. A save
    /// stops and asks rather than write over the other change.
    private(set) var conflicts: Set<Entry.ID> = []
    private(set) var saveErrors: [Entry.ID: String] = [:]
    /// Changed files in the site's repo, for Publish.
    private(set) var changes: [GitChange] = []
    /// Uploads in flight, for the bar at the bottom of the window.
    private(set) var uploads: [Upload] = []
    /// The last thing that went wrong with a new entry or an upload.
    var lastError: String?
    /// Whether the preview window is open, for the toolbar's eye button.
    var previewOpen = false
    /// Counts saves, so the preview knows to reload.
    private(set) var saveCount = 0
    /// Bumped when an entry is reread from disk, so its editor starts over.
    private(set) var revisions: [Entry.ID: Int] = [:]

    var selectedItem: String?
    var selectedEntry: [String: Entry.ID] = [:]

    private static let siteKey = "sitePath"

    var siteName: String { siteURL?.lastPathComponent ?? "Canteiro" }

    /// Reopen the last site, or the usual one on this Mac.
    func restore() async {
        let saved = UserDefaults.standard.string(forKey: Self.siteKey)
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Projects/among-the-stones").path
        for path in [saved, fallback].compactMap({ $0 }) where Self.isSite(URL(fileURLWithPath: path)) {
            await open(URL(fileURLWithPath: path))
            return
        }
    }

    func chooseSite() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Site"
        panel.message = "Choose a site folder with a keystatic.config.ts."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Self.isSite(url) else {
            phase = .failed("\(url.lastPathComponent) has no keystatic.config.ts.")
            return
        }
        Task { await open(url) }
    }

    func reload() {
        guard let siteURL else { return }
        Task { await open(siteURL) }
    }

    nonisolated static func isSite(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: "keystatic.config.ts").path)
    }

    func open(_ url: URL) async {
        phase = .loading
        siteURL = url
        UserDefaults.standard.set(url.path, forKey: Self.siteKey)
        do {
            let schema = try await SchemaLoader.load(site: url)
            let loaded = await Task.detached(priority: .userInitiated) { Self.readAll(schema, site: url) }.value
            self.schema = schema
            entries = loaded.entries
            singletons = loaded.singletons
            problems = loaded.problems
            refreshChanges()
            if selectedItem == nil || schema.item(selectedItem!) == nil {
                selectedItem = schema.groups.first?.items.first?.key
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    struct Loaded: Sendable {
        var entries: [String: [Entry]] = [:]
        var singletons: [String: Entry] = [:]
        var problems: [String] = []
    }

    nonisolated static func readAll(_ schema: SiteSchema, site: URL) -> Loaded {
        var loaded = Loaded()
        for item in schema.items {
            do {
                switch item.kind {
                case .collection:
                    loaded.entries[item.key] = sorted(try ContentLoader.entries(of: item, in: site), item: item)
                case .singleton:
                    loaded.singletons[item.key] = try ContentLoader.singleton(item, in: site)
                }
            } catch {
                loaded.problems.append(error.localizedDescription)
            }
        }
        return loaded
    }

    /// Newest first when entries have a date, then by an `order` number,
    /// else by title.
    nonisolated static func sorted(_ list: [Entry], item: SchemaItem) -> [Entry] {
        if let date = item.dateField {
            return list.sorted { ($0.data[date.key]?.date ?? .distantPast) > ($1.data[date.key]?.date ?? .distantPast) }
        }
        if let order = item.dataFields.first(where: { $0.type == "integer" }) {
            return list.sorted { ($0.data[order.key]?.int ?? 0, $0.slug) < ($1.data[order.key]?.int ?? 0, $1.slug) }
        }
        return list.sorted { title(of: $0, item: item).localizedStandardCompare(title(of: $1, item: item)) == .orderedAscending }
    }

    /// The name an entry goes by in lists and pickers.
    nonisolated static func title(of entry: Entry, item: SchemaItem) -> String {
        if let field = item.titleField, let text = entry.data[field.key]?.string, !text.isEmpty {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        return entry.slug
    }

    // MARK: Saving

    /// The entry as the store has it now (after any earlier save).
    func current(_ item: SchemaItem, id: Entry.ID) -> Entry? {
        item.kind == .singleton ? singletons[item.key] : entries[item.key]?.first { $0.id == id }
    }

    /// Writes the edits to the entry's file. Does nothing when nothing
    /// changed, and stops when the file changed on disk since it was read,
    /// unless `overwrite` says to write over it.
    func save(_ item: SchemaItem, id: Entry.ID, data: FieldValue, body: String?, overwrite: Bool = false) {
        guard let siteURL, let entry = current(item, id: id) else { return }
        guard let text = FileWriter.text(for: entry, data: data, body: body, format: item.format) else { return }
        let onDisk = try? String(contentsOf: entry.url, encoding: .utf8)
        if onDisk != entry.raw && !overwrite {
            conflicts.insert(id)
            return
        }
        do {
            try text.write(to: entry.url, atomically: true, encoding: .utf8)
            let saved = try ContentLoader.read(entry.url, slug: entry.slug, site: siteURL, hasBody: item.format.contentField != nil)
            replace(saved, in: item)
            conflicts.remove(id)
            saveErrors[id] = nil
            saveCount += 1
            refreshChanges()
        } catch {
            saveErrors[id] = error.localizedDescription
        }
    }

    /// Drops the edits and rereads the file from disk.
    func reread(_ item: SchemaItem, id: Entry.ID) {
        guard let siteURL, let entry = current(item, id: id) else { return }
        do {
            let fresh = try ContentLoader.read(entry.url, slug: entry.slug, site: siteURL, hasBody: item.format.contentField != nil)
            replace(fresh, in: item)
            conflicts.remove(id)
            saveErrors[id] = nil
            revisions[id, default: 0] += 1
        } catch {
            saveErrors[id] = error.localizedDescription
        }
    }

    private func replace(_ entry: Entry, in item: SchemaItem) {
        if item.kind == .singleton {
            singletons[item.key] = entry
        } else if let index = entries[item.key]?.firstIndex(where: { $0.id == entry.id }) {
            entries[item.key]?[index] = entry
        }
    }

    // MARK: New entries

    /// Writes a new entry and selects it. The file name is the slug, made
    /// unique with -2, -3 if it's taken.
    @discardableResult
    func create(_ item: SchemaItem, slug: String, data: FieldValue, body: String? = nil) throws -> Entry {
        guard let siteURL, item.kind == .collection else { throw ContentLoader.Failure.unreadable(item.label, "not a collection") }
        let folder = siteURL.appending(path: item.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = slug
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: "\(name).\(item.fileExtension)").path) {
            name = "\(slug)-\(n)"
            n += 1
        }
        guard case .object(let pairs) = data else { throw ContentLoader.Failure.unreadable(item.label, "no fields") }
        let yaml = pairs.flatMap { YAMLEmitter.lines(key: $0.key, value: $0.value, indent: 0) }.joined(separator: "\n")
        let text = item.format.contentField != nil ? "---\n\(yaml)\n---\n" + (body ?? "") : yaml + "\n"
        let url = folder.appending(path: "\(name).\(item.fileExtension)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let entry = try ContentLoader.read(url, slug: name, site: siteURL, hasBody: item.format.contentField != nil)
        entries[item.key] = Self.sorted((entries[item.key] ?? []) + [entry], item: item)
        selectedItem = item.key
        selectedEntry[item.key] = entry.id
        saveCount += 1
        refreshChanges()
        return entry
    }

    /// A new entry's fields in schema order: the given values, then for each
    /// field the site needs (required ones, switches, menus) its default.
    func newData(_ item: SchemaItem, _ values: [String: FieldValue]) -> FieldValue {
        var pairs: [FieldPair] = []
        for field in item.dataFields {
            if let value = values[field.key] {
                pairs.append(FieldPair(key: field.key, value: value))
            } else if field.type == "checkbox" {
                pairs.append(FieldPair(key: field.key, value: .bool(false)))
            } else if field.type == "select", let value = field.defaultString ?? field.options?.first?.value {
                pairs.append(FieldPair(key: field.key, value: .string(value)))
            }
        }
        return .object(pairs)
    }

    /// The first dated stream of short text: the asides.
    var streamItem: SchemaItem? { schema?.items.first { $0.isStream } }

    /// Saves a new aside: the text, now, and the language picked.
    func createAside(text: String, language: String?) throws {
        guard let item = streamItem, let textField = item.textField else { return }
        let now = Date.now
        let slug = Self.stamp(now, "yyyy-MM-dd-HHmm")
        var values: [String: FieldValue] = [textField.key: .string(text)]
        if let slugField = item.slugField { values[slugField] = .string(slug) }
        if let date = item.dateField { values[date.key] = Self.dateValue(now, type: date.type) }
        if let language, let field = item.dataFields.first(where: { $0.type == "select" && $0.key.hasPrefix("lang") }) {
            values[field.key] = .string(language)
        }
        try create(item, slug: slug, data: newData(item, values))
    }

    // MARK: Uploads

    struct Upload: Identifiable, Sendable {
        let id = UUID()
        let name: String
        var progress: Double = 0
    }

    /// Puts a file on R2 and returns its public address.
    func upload(_ file: URL, key: String, contentType: String, name: String) async throws -> String {
        let client = try R2Client.fromSettings()
        let upload = Upload(name: name)
        uploads.append(upload)
        defer { uploads.removeAll { $0.id == upload.id } }
        try await client.put(file, key: key, contentType: contentType) { fraction in
            Task { @MainActor in
                if let i = self.uploads.firstIndex(where: { $0.id == upload.id }) { self.uploads[i].progress = fraction }
            }
        }
        return R2Settings.publicURL(for: key)
    }

    nonisolated static func stamp(_ date: Date, _ format: String, utc: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if utc { f.timeZone = TimeZone(identifier: "UTC") }
        f.dateFormat = format
        return f.string(from: date)
    }

    /// A date the way Keystatic writes it: 2026-10-04, or UTC with milliseconds.
    nonisolated static func dateValue(_ date: Date, type: String) -> FieldValue {
        // Keystatic saves to the minute.
        let date = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        return type == "date"
            ? .date(date, raw: stamp(date, "yyyy-MM-dd"))
            : .date(date, raw: stamp(date, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", utc: true))
    }

    // MARK: Publishing

    func refreshChanges() {
        guard let siteURL else { return }
        Task {
            let found = await Task.detached { (try? Git.status(siteURL)) ?? [] }.value
            if self.siteURL == siteURL { changes = found }
        }
    }

    /// Changes to files Keystatic manages: the ones Publish ticks for you.
    /// Code changes in progress are listed but left unticked.
    var contentChanges: [GitChange] { changes.filter { isContent($0.path) } }

    func isContent(_ path: String) -> Bool {
        guard let schema else { return false }
        return schema.items.contains { item in
            switch item.kind {
            case .singleton:
                return path == item.path + "." + item.fileExtension
            case .collection:
                let folder = item.path.replacingOccurrences(of: "/**", with: "").replacingOccurrences(of: "/*", with: "")
                return path.hasPrefix(folder + "/")
            }
        }
    }

    /// The entry's title for a changed file, or the section's name for a
    /// settings file.
    func title(forPath path: String) -> String? {
        guard let schema else { return nil }
        for item in schema.items {
            if item.kind == .singleton, path == item.path + "." + item.fileExtension { return item.label }
            if let entry = entries[item.key]?.first(where: { $0.id == path }) { return Self.title(of: entry, item: item) }
        }
        return nil
    }

    /// The site address of what's open, from Keystatic's previewUrl. A
    /// settings page has none, so it previews the home page.
    var previewPath: String? {
        guard let key = selectedItem, let item = schema?.item(key) else { return nil }
        if item.kind == .singleton { return "/" }
        guard let template = item.previewUrl, let id = selectedEntry[key],
              let entry = entries[key]?.first(where: { $0.id == id }) else { return nil }
        return template.replacingOccurrences(of: "{slug}", with: entry.slug)
    }

    func count(_ item: SchemaItem) -> Int? {
        item.kind == .collection ? entries[item.key]?.count ?? 0 : nil
    }
}
