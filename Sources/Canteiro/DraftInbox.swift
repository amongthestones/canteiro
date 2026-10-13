import AppKit
import Foundation
import Observation

/// A draft waiting in the inbox folder.
struct InboxDraft: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let modified: Date
    /// The first lines of the text, for the list.
    let preview: String
}

/// A writing app's folder, from the site's canteiro.json, such as a folder in
/// iA Writer's iCloud library. Drafts are written there, on the phone or the
/// Mac, and imported as entries. An imported file moves to
/// Imported/, so a piece only ever lives in one place: the writing app until
/// it's imported, the site after.
@MainActor @Observable
final class DraftInbox {
    /// The sidebar's tag for the inbox. Schema keys never have a dot.
    static let sidebarKey = "canteiro.inbox"
    /// A folder chosen on this Mac, over the site's.
    private static let folderKey = "inboxPath"

    private(set) var drafts: [InboxDraft] = []
    var selected: URL?
    /// Edits not yet written, by file.
    private var unsaved: [URL: String] = [:]
    /// Each open file as last read or written. A save checks the file still
    /// says this, so an edit from the writing app is never written over.
    private var known: [URL: String] = [:]
    private(set) var conflicts: Set<URL> = []
    private(set) var saveErrors: [URL: String] = [:]
    /// Why the folder can't be read, if it can't.
    private(set) var problem: String?
    /// Nil when the site has no inbox.
    private(set) var folder: URL?
    /// The collection drafts become entries of.
    private(set) var collection: String?
    /// "iA Writer", or a stand-in when the config doesn't name the app.
    private(set) var app = "the writing app"
    private var watcher: DispatchSourceFileSystemObject?

    /// No folder until a site with an inbox opens; tests pass one.
    init(folder: URL? = nil, collection: String? = nil) {
        self.folder = folder
        self.collection = collection
        refresh()
        watch()
    }

    /// Follows the open site: its inbox, or none.
    func configure(_ config: SiteConfig) {
        let chosen = UserDefaults.standard.string(forKey: Self.folderKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
        let next = config.inboxFolder.map { chosen ?? $0 }
        collection = config.inbox?.importInto
        app = config.inbox?.app ?? "the writing app"
        guard next != folder else { return }
        folder = next
        selected = nil
        refresh()
        watch()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        panel.prompt = "Watch"
        panel.message = "Choose the folder in \(app) your drafts go in."
        guard panel.runModal() == .OK, let url = panel.url, folder != nil else { return }
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        refresh()
        watch()
    }

    func refresh() {
        let fm = FileManager.default
        guard let folder else {
            drafts = []
            problem = nil
            return
        }
        do {
            let names = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])
            // A file iCloud hasn't brought down yet is a hidden .Name.md.icloud;
            // ask for it, and the watcher picks it up once it lands.
            for url in names where url.pathExtension == "icloud" && url.lastPathComponent.hasPrefix(".") {
                let real = url.deletingLastPathComponent().appending(path: String(url.deletingPathExtension().lastPathComponent.dropFirst()))
                try? fm.startDownloadingUbiquitousItem(at: real)
            }
            drafts = names
                .filter { !$0.lastPathComponent.hasPrefix(".") && Self.extensions.contains($0.pathExtension.lowercased()) }
                .compactMap(Self.read)
                .sorted { $0.modified > $1.modified }
            if selected.map({ url in !drafts.contains { $0.url == url } }) ?? true { selected = drafts.first?.url }
            problem = nil
        } catch {
            drafts = []
            problem = fm.fileExists(atPath: folder.path)
                ? "Canteiro can't read \(folder.lastPathComponent). Allow it under System Settings › Privacy & Security › Files and Folders, or choose the folder again."
                : "There's no folder at \(folder.path)."
        }
    }

    static let extensions: Set<String> = ["md", "markdown", "txt"]

    nonisolated static func read(_ url: URL) -> InboxDraft? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let parsed = parse(text, name: url.deletingPathExtension().lastPathComponent)
        let preview = parsed.body.split(separator: "\n", omittingEmptySubsequences: true).prefix(2).joined(separator: " ")
        return InboxDraft(url: url, title: parsed.title, modified: modified, preview: String(preview.prefix(200)))
    }

    /// A draft's title, any frontmatter, and the body to import. The title
    /// is frontmatter's `title`, else a first `# heading` (taken out of the
    /// body, since the post shows its title), else the file name.
    nonisolated static func parse(_ text: String, name: String) -> (title: String, fields: [FieldPair], body: String) {
        var fields: [FieldPair] = []
        var body = text
        if text.hasPrefix("---\n") || text.hasPrefix("---\r\n") {
            let parts = YAMLReader.splitFrontmatter(text)
            if case .object(let pairs)? = try? YAMLReader.parse(parts.yaml) {
                fields = pairs
                body = parts.body
            }
        }
        body = String(body.drop { $0 == "\n" || $0 == "\r" })
        var title = fields.first { $0.key == "title" }?.value.string ?? ""
        if let first = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           first.hasPrefix("# ") {
            if title.isEmpty { title = first.dropFirst(2).trimmingCharacters(in: .whitespaces) }
            body = String(body.dropFirst(first.count).drop { $0 == "\n" || $0 == "\r" })
        }
        if title.isEmpty { title = name }
        return (title, fields.filter { $0.key != "title" }, body)
    }

    // MARK: Editing

    /// The file's text for the editor, remembered as what's on disk.
    func open(_ url: URL) -> String {
        if let text = unsaved[url] { return text }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        known[url] = text
        return text
    }

    func edit(_ url: URL, _ text: String) {
        unsaved[url] = text == known[url] ? nil : text
    }

    func hasUnsaved(_ url: URL) -> Bool { unsaved[url] != nil }

    /// Writes the edits, unless the writing app (or iCloud) changed the file since.
    func save(_ url: URL, overwrite: Bool = false) {
        guard let text = unsaved[url] else { return }
        let onDisk = try? String(contentsOf: url, encoding: .utf8)
        guard overwrite || onDisk == known[url] else {
            conflicts.insert(url)
            return
        }
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: nil) { target in
            do { try text.write(to: target, atomically: true, encoding: .utf8) } catch { failure = error }
        }
        if let failure {
            saveErrors[url] = failure.localizedDescription
            return
        }
        known[url] = text
        unsaved[url] = nil
        conflicts.remove(url)
        saveErrors[url] = nil
    }

    /// Drops the edits and reads the file again.
    func revert(_ url: URL) {
        unsaved[url] = nil
        conflicts.remove(url)
        saveErrors[url] = nil
    }

    /// Whether the file now says something other than what the editor
    /// last saw, as when the phone saved it.
    func changedOnDisk(_ url: URL) -> Bool {
        guard let known = known[url] else { return false }
        return (try? String(contentsOf: url, encoding: .utf8)) != known
    }

    /// Makes the draft an entry (a draft there too) and moves the file to
    /// Imported/.
    func importDraft(_ draft: InboxDraft, into item: SchemaItem, store: SiteStore) throws {
        save(draft.url)
        if conflicts.contains(draft.url) { throw ImportFailure.conflict }
        let text = try String(contentsOf: draft.url, encoding: .utf8)
        let parsed = Self.parse(text, name: draft.url.deletingPathExtension().lastPathComponent)
        // Frontmatter only fills fields the post has.
        let postFields = Set(item.dataFields.map(\.key))
        var values = Dictionary(parsed.fields.filter { postFields.contains($0.key) }.map { ($0.key, $0.value) }) { a, _ in a }
        values["draft"] = nil
        try store.createEntry(item, title: parsed.title, body: parsed.body, values: values)

        guard let done = folder?.appending(path: "Imported", directoryHint: .isDirectory) else { return }
        try FileManager.default.createDirectory(at: done, withIntermediateDirectories: true)
        var target = done.appending(path: draft.url.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = done.appending(path: "\(draft.url.deletingPathExtension().lastPathComponent) \(n).\(draft.url.pathExtension)")
            n += 1
        }
        try FileManager.default.moveItem(at: draft.url, to: target)
        known[draft.url] = nil
        refresh()
    }

    enum ImportFailure: LocalizedError {
        case conflict
        var errorDescription: String? {
            "The file changed elsewhere since Canteiro read it. Choose which version to keep first."
        }
    }

    /// Refreshes when a file is added, removed or renamed in the folder.
    private func watch() {
        watcher?.cancel()
        watcher = nil
        guard let folder else { return }
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
