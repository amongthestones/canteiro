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
    nonisolated private static func sorted(_ list: [Entry], item: SchemaItem) -> [Entry] {
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
