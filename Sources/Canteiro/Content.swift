import Foundation

/// One file of the site: a collection entry or a singleton.
struct Entry: Sendable, Identifiable, Hashable {
    /// Path from the site folder, e.g. src/content/posts/vibe-check.md.
    let id: String
    /// The entry's address within its collection: the file name without its
    /// extension, with folders for nested collections (books/moon-road/01).
    let slug: String
    let url: URL
    var data: FieldValue
    /// The text after the frontmatter, for entries with a body.
    var body: String?

    static func == (a: Entry, b: Entry) -> Bool { a.id == b.id && a.data == b.data && a.body == b.body }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ContentLoader {
    enum Failure: LocalizedError {
        case unreadable(String, String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let path, let reason): return "\(path): \(reason)"
            }
        }
    }

    /// Every entry of a collection. Keystatic's path ends in `*` (files in
    /// the folder) or `**` (files in any subfolder too).
    static func entries(of item: SchemaItem, in site: URL) throws -> [Entry] {
        let recursive = item.path.hasSuffix("**")
        let folderPath = item.path.replacingOccurrences(of: "/**", with: "").replacingOccurrences(of: "/*", with: "")
        let folder = site.appending(path: folderPath, directoryHint: .isDirectory)
        let ext = item.fileExtension

        var files: [URL] = []
        let fm = FileManager.default
        if recursive {
            let walker = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let url = walker?.nextObject() as? URL {
                if url.pathExtension == ext { files.append(url) }
            }
        } else {
            let names = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            files = names.filter { $0.pathExtension == ext }
        }

        return try files.map { url in
            let relative = String(url.path.dropFirst(folder.path.count + 1))
            let slug = String(relative.dropLast(ext.count + 1))
            return try read(url, slug: slug, site: site, hasBody: item.format.contentField != nil)
        }
    }

    /// A singleton's one file, or nil when it hasn't been made yet.
    static func singleton(_ item: SchemaItem, in site: URL) throws -> Entry? {
        let url = site.appending(path: item.path + "." + item.fileExtension)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url, slug: item.key, site: site, hasBody: item.format.contentField != nil)
    }

    static func read(_ url: URL, slug: String, site: URL, hasBody: Bool) throws -> Entry {
        let id = String(url.path.dropFirst(site.path.count + 1))
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if hasBody {
                let parts = YAMLReader.splitFrontmatter(text)
                return Entry(id: id, slug: slug, url: url, data: try YAMLReader.parse(parts.yaml), body: parts.body)
            }
            return Entry(id: id, slug: slug, url: url, data: try YAMLReader.parse(text), body: nil)
        } catch {
            throw Failure.unreadable(id, error.localizedDescription)
        }
    }
}
