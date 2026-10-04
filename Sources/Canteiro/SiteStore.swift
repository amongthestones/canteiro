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

    func count(_ item: SchemaItem) -> Int? {
        item.kind == .collection ? entries[item.key]?.count ?? 0 : nil
    }
}
