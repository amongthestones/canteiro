import Foundation
import Testing
@testable import Canteiro

/// Image and file fields put their files where Keystatic 0.5 and 0.6 do
/// (its serializeEntryToFiles and getSrcPrefix), so the two can share a site.
@Suite struct AssetTests {
    let site = URL(fileURLWithPath: "/site")

    private func item(_ kind: String, path: String, field: String) throws -> SchemaItem {
        let json = #"{"key":"k","kind":"\#(kind)","label":"K","path":"\#(path)","format":"yaml","fields":[\#(field)]}"#
        return try JSONDecoder().decode(SchemaItem.self, from: Data(json.utf8))
    }

    @Test func aCollectionWithADirectoryFilesBySlug() throws {
        let item = try item("collection", path: "src/content/posts/*",
                            field: #"{"key":"cover","type":"image","directory":"src/assets/posts/","publicPath":"../../assets/posts/"}"#)
        let spec = item.fields[0]
        let place = AssetPlace(site: site, item: item, slug: "first-post")
        let value = place.value(for: URL(fileURLWithPath: "/tmp/IMG_0042.JPG"), spec, path: ["cover"])
        #expect(value == "../../assets/posts/first-post/cover.JPG")
        #expect(place.url(for: value, spec)?.path == "/site/src/assets/posts/first-post/cover.JPG")
    }

    @Test func withoutADirectoryTheFileSitsNextToTheEntry() throws {
        let item = try item("collection", path: "src/content/posts/*", field: #"{"key":"cover","type":"image"}"#)
        let spec = item.fields[0]
        let place = AssetPlace(site: site, item: item, slug: "first-post")
        let value = place.value(for: URL(fileURLWithPath: "/tmp/a.png"), spec, path: ["cover"])
        #expect(value == "cover.png")
        #expect(place.url(for: value, spec)?.path == "/site/src/content/posts/first-post/cover.png")
    }

    @Test func aFolderPerEntryCollectionKeepsItsFolder() throws {
        let item = try item("collection", path: "src/content/books/*/index", field: #"{"key":"art","type":"file"}"#)
        let place = AssetPlace(site: site, item: item, slug: "moon-road")
        #expect(place.base == "src/content/books/moon-road/index")
    }

    @Test func aSingletonHasNoSlugFolder() throws {
        let item = try item("singleton", path: "src/data/home",
                            field: #"{"key":"photo","type":"image","directory":"src/assets/home","publicPath":"/src/assets/home/"}"#)
        let spec = item.fields[0]
        let place = AssetPlace(site: site, item: item, slug: "home")
        let value = place.value(for: URL(fileURLWithPath: "/tmp/valley.jpg"), spec, path: ["photo"])
        #expect(value == "/src/assets/home/photo.jpg")
        #expect(place.url(for: value, spec)?.path == "/site/src/assets/home/photo.jpg")
    }

    @Test func aFieldInAGroupIsNamedByItsPath() throws {
        let item = try item("singleton", path: "src/data/home", field: #"{"key":"photo","type":"image","publicPath":"/images"}"#)
        let place = AssetPlace(site: site, item: item, slug: nil)
        #expect(place.value(for: URL(fileURLWithPath: "/tmp/x.webp"), item.fields[0], path: ["hero", "photo"]) == "/images/hero/photo.webp")
    }

    @Test func aValueFromSomewhereElseIsNotOurs() throws {
        let item = try item("collection", path: "src/content/posts/*",
                            field: #"{"key":"cover","type":"image","publicPath":"/images/posts/"}"#)
        let place = AssetPlace(site: site, item: item, slug: "first-post")
        #expect(place.url(for: "https://media.example.com/a.jpg", item.fields[0]) == nil)
        #expect(place.url(for: "/images/posts/other-post/cover.jpg", item.fields[0]) == nil)
    }

    /// Storing, replacing under the same name, and trashing, in a real folder.
    @Test func storeReplaceAndTrash() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "canteiro-assets-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let item = try item("collection", path: "src/content/posts/*",
                            field: #"{"key":"cover","type":"image","directory":"src/assets/posts","publicPath":"/src/assets/posts/"}"#)
        let spec = item.fields[0]
        let place = AssetPlace(site: root, item: item, slug: "first-post")
        let source = root.appending(path: "in.jpg")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source)

        let value = try place.store(source, spec, path: ["cover"])
        let file = try #require(place.url(for: value, spec))
        #expect(try String(contentsOf: file, encoding: .utf8) == "one")

        try Data("two".utf8).write(to: source)
        _ = try place.store(source, spec, path: ["cover"])
        #expect(try String(contentsOf: file, encoding: .utf8) == "two")
        // Choosing the field's own file changes nothing.
        #expect(try place.store(file, spec, path: ["cover"]) == value)

        let data = FieldValue.object([FieldPair(key: "cover", value: .string(value))])
        #expect(place.files(item.fields, in: data).map(\.0) == [file])
        let trashed = try place.trash(file, spec)
        defer { if let trashed { try? fm.removeItem(at: trashed) } }
        #expect(!fm.fileExists(atPath: file.path))
        #expect(!fm.fileExists(atPath: file.deletingLastPathComponent().path), "the entry's emptied folder goes")
    }

    /// Every image and file the site's entries name is where Keystatic
    /// would put it, so Canteiro reads the same files.
    @Test(.enabled(if: SiteTests.hasSite))
    func everyFileTheSiteNamesIsFound() async throws {
        let schema = try await SchemaLoader.load(site: SiteTests.site)
        let loaded = SiteStore.readAll(schema, site: SiteTests.site)
        for item in schema.items {
            let entries = item.kind == .singleton ? [loaded.singletons[item.key] ?? nil].compactMap { $0 } : loaded.entries[item.key] ?? []
            for entry in entries {
                let place = AssetPlace(site: SiteTests.site, item: item, slug: entry.slug)
                for (file, _) in place.files(item.dataFields, in: entry.data) {
                    #expect(FileManager.default.fileExists(atPath: file.path), "\(entry.id): \(file.path)")
                }
            }
        }
    }
}
