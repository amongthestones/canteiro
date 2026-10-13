import AppKit
import AVFoundation
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
    /// The site's canteiro.json, or the empty config.
    private(set) var config = SiteConfig()
    private(set) var entries: [String: [Entry]] = [:]
    private(set) var singletons: [String: Entry] = [:]
    /// Files that didn't parse. Shown, not hidden: a broken file is worth knowing about.
    private(set) var problems: [String] = []
    /// Why canteiro.json didn't load, for Settings. Also in `problems`.
    private(set) var configProblem: String?

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
    /// The collection a New Entry sheet is open for.
    var newEntryItem: SchemaItem?
    var selectedEntry: [String: Entry.ID] = [:]

    private static let siteKey = "sitePath"

    var siteName: String { siteURL?.lastPathComponent ?? "Canteiro" }

    /// Reopen the last site, if it's still there.
    func restore() async {
        guard let saved = UserDefaults.standard.string(forKey: Self.siteKey),
              Self.isSite(URL(fileURLWithPath: saved)) else { return }
        await open(URL(fileURLWithPath: saved))
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
            do {
                config = try SiteConfig.load(site: url)
                configProblem = nil
            } catch {
                config = SiteConfig()
                configProblem = error.localizedDescription
                problems.insert(error.localizedDescription, at: 0)
            }
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

    /// Moves entries' files to the Trash, so a slip can be put back from
    /// there (or from git until it's published). The next entry in the
    /// list takes the selection. Returns where the files went.
    @discardableResult
    func trash(_ item: SchemaItem, ids: Set<Entry.ID>) -> [URL] {
        guard item.kind == .collection, let list = entries[item.key] else { return [] }
        var gone: Set<Entry.ID> = []
        var trashed: [URL] = []
        for entry in list where ids.contains(entry.id) {
            do {
                // Its images and files go too, as in Keystatic.
                if let siteURL {
                    let place = AssetPlace(site: siteURL, item: item, slug: entry.slug)
                    for (file, field) in place.files(item.dataFields, in: entry.data) {
                        if let moved = try place.trash(file, field) { trashed.append(moved) }
                    }
                }
                var moved: NSURL?
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &moved)
                if let moved { trashed.append(moved as URL) }
                gone.insert(entry.id)
            } catch {
                lastError = "\(entry.url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        guard !gone.isEmpty else { return trashed }
        if let selected = selectedEntry[item.key], gone.contains(selected),
           let index = list.firstIndex(where: { $0.id == selected }) {
            let next = list[index...].first { !gone.contains($0.id) } ?? list[..<index].last { !gone.contains($0.id) }
            selectedEntry[item.key] = next?.id
        }
        entries[item.key] = list.filter { !gone.contains($0.id) }
        for id in gone {
            conflicts.remove(id)
            saveErrors[id] = nil
        }
        saveCount += 1
        refreshChanges()
        return trashed
    }

    /// A new entry's fields in schema order: the given values, then each
    /// field's default from the config (a post's kind, chapter 1, a date of
    /// now), as Keystatic fills a new entry in.
    func newData(_ item: SchemaItem, _ values: [String: FieldValue]) -> FieldValue {
        .object(item.dataFields.compactMap { field in
            (values[field.key] ?? Self.initial(field)).map { FieldPair(key: field.key, value: $0) }
        })
    }

    /// A field's value in a new entry, or nil to leave it out of the file.
    nonisolated static func initial(_ field: FieldSpec) -> FieldValue? {
        switch field.type {
        case "checkbox":
            return .bool(field.defaultBool ?? false)
        case "select":
            return (field.defaultString ?? field.options?.first?.value).map(FieldValue.string)
        case "multiselect":
            guard let list = field.defaultStrings, !list.isEmpty else { return nil }
            return .array(list.map(FieldValue.string))
        case "integer":
            return field.defaultInt.map(FieldValue.int)
        case "date", "datetime":
            return field.defaultKind == nil ? nil : dateValue(.now, type: field.type)
        case "text":
            return field.defaultString.map(FieldValue.string)
        case "conditional":
            guard let menu = field.discriminant, let picked = initial(menu)?.string else { return nil }
            let sub = field.values?.first { $0.key == picked }
            return .object([FieldPair(key: "discriminant", value: .string(picked)),
                            FieldPair(key: "value", value: sub.flatMap(initial) ?? .null)])
        default:
            return nil
        }
    }

    /// A new entry named by its title: the file is the title as a slug,
    /// the config's defaults are filled in, and it starts as a draft, so a
    /// publish can't put it on the site half-written.
    func createEntry(_ item: SchemaItem, title: String, body: String = "", values: [String: FieldValue] = [:]) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = values
        if let slugField = item.slugField { values[slugField] = .string(title) }
        if item.dataFields.contains(where: { $0.key == "draft" && $0.type == "checkbox" }) { values["draft"] = .bool(true) }
        try create(item, slug: Slug.make(title), data: newData(item, values), body: item.bodyField == nil ? nil : body)
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

    /// A collection of podcast episodes: one canteiro.json names, with an
    /// audio address field.
    func isEpisodes(_ item: SchemaItem) -> Bool {
        item.kind == .collection && config.isEpisodes(item.key)
            && item.dataFields.contains { $0.key == config.audioField }
    }

    /// A dropped MP3 becomes a draft episode: its length read, the file put
    /// on R2 in the show's audio folder, the next number and a guid filled in.
    func createEpisode(_ item: SchemaItem, from file: URL) async {
        do {
            let show = URL(fileURLWithPath: item.folder).lastPathComponent
            let seconds = try await AVURLAsset(url: file).load(.duration).seconds
            let base = Slug.make(file.deletingPathExtension().lastPathComponent)
            let key = config.audioFolder(show: show) + "\(base).\(file.pathExtension.lowercased())"
            let number = (entries[item.key]?.compactMap { $0.data[config.numberField]?.int }.max() ?? 0) + 1
            let url = try await upload(file, key: key, contentType: "audio/mpeg", name: file.lastPathComponent)
            try addEpisode(item, slug: base, number: number, seconds: seconds, audioURL: url)
        } catch {
            lastError = "\(file.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// The draft entry for an uploaded episode.
    func addEpisode(_ item: SchemaItem, slug: String, number: Int, seconds: Double, audioURL: String) throws {
        let show = URL(fileURLWithPath: item.folder).lastPathComponent
        var values: [String: FieldValue] = [:]
        func set(_ key: String, _ value: FieldValue) {
            if item.dataFields.contains(where: { $0.key == key }) { values[key] = value }
        }
        set("title", .string("Episode \(number)"))
        set("draft", .bool(true))
        if let date = item.dateField { values[date.key] = Self.dateValue(.now, type: date.type) }
        set(config.numberField, .int(number))
        set(config.guidField, .string(config.guid(show: show, number: number)))
        set(config.audioField, .string(audioURL))
        set(config.durationField, .string(Self.duration(seconds)))
        set("mimeType", .string("audio/mpeg"))
        try create(item, slug: slug, data: newData(item, values), body: "")
    }

    /// HH:MM:SS, as <itunes:duration> takes it.
    nonisolated static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    // MARK: Uploads

    struct Upload: Identifiable, Sendable {
        let id = UUID()
        let name: String
        var progress: Double = 0
    }

    /// Puts a file in the site's bucket and returns its public address.
    func upload(_ file: URL, key: String, contentType: String, name: String) async throws -> String {
        guard let bucket = config.uploads?.bucket, let address = config.publicURL(for: key) else { throw UploadFailure.noUploads }
        let client = try R2Client.fromSettings(bucket: bucket)
        let upload = Upload(name: name)
        uploads.append(upload)
        defer { uploads.removeAll { $0.id == upload.id } }
        try await client.put(file, key: key, contentType: contentType) { fraction in
            Task { @MainActor in
                if let i = self.uploads.firstIndex(where: { $0.id == upload.id }) { self.uploads[i].progress = fraction }
            }
        }
        return address
    }

    enum UploadFailure: LocalizedError {
        case noUploads
        var errorDescription: String? {
            "This site has no uploads set up. Add an \"uploads\" block with the bucket and public address to \(SiteConfig.fileName)."
        }
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
