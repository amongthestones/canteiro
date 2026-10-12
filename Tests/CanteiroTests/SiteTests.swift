import Foundation
import Testing
@testable import Canteiro

/// Reads the real Among the Stones site, when it's on this Mac.
@Suite struct SiteTests {
    static let site = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Projects/among-the-stones")

    @Test(.enabled(if: SiteStore.isSite(site)))
    func readsEveryFile() async throws {
        let schema = try await SchemaLoader.load(site: Self.site)
        #expect(schema.groups.map(\.name) == ["Writing", "Podcasts", "Tales", "Site"])
        let loaded = SiteStore.readAll(schema, site: Self.site)
        #expect(loaded.problems.isEmpty, "\(loaded.problems)")
        #expect((loaded.entries["posts"]?.count ?? 0) > 200)
        #expect(loaded.entries["fiction"]?.first { $0.slug == "the-dry-ford" }?.data["work"] == .string("moon-road"))
        #expect(loaded.singletons["talesSettings"]?.data["glossary"]?["terms"]?.array?.isEmpty == false)
        #expect(loaded.singletons["tags"]?.data["tags"]?.array?.isEmpty == false)
        // Every post with a date has one that parses.
        let undated = loaded.entries["posts"]?.filter { $0.data["date"] != nil && $0.data["date"]?.date == nil } ?? []
        #expect(undated.isEmpty, "\(undated.map(\.id))")
    }

    /// Every file on the site: splicing unchanged data rebuilds it byte for
    /// byte, a fresh rewrite of every field reads back the same, and JSON
    /// matches Keystatic's own output.
    @Test(.enabled(if: SiteStore.isSite(site)))
    func everyFileRoundTrips() async throws {
        let schema = try await SchemaLoader.load(site: Self.site)
        let loaded = SiteStore.readAll(schema, site: Self.site)
        var checked = 0
        for item in schema.items {
            let entries = item.kind == .collection ? loaded.entries[item.key] ?? [] : [loaded.singletons[item.key]].compactMap { $0 }
            for entry in entries {
                checked += 1
                if item.format.data == "json" && item.format.contentField == nil {
                    #expect(JSONEmitter.document(entry.data) == entry.raw, "\(entry.id) JSON style")
                    continue
                }
                let yamlText = item.format.contentField != nil ? YAMLReader.splitFrontmatter(entry.raw).yaml : entry.raw
                #expect(YAMLSplicer.yaml(original: yamlText, old: entry.data, new: entry.data) == yamlText, "\(entry.id) splice")

                guard case .object(let pairs) = entry.data else { continue }
                let fresh = pairs.flatMap { YAMLEmitter.lines(key: $0.key, value: $0.value, indent: 0) }.joined(separator: "\n")
                let reread = try YAMLReader.parse(fresh)
                #expect(Self.same(reread, entry.data), "\(entry.id) rewrite:\n\(fresh)")
            }
        }
        #expect(checked > 280)
    }

    /// The editor hides a blank line at the top of a body; putting it back
    /// gives every body on the site back exactly. The site dropped those lines
    /// on 2026-10-04, so few or none are left to hide.
    @Test(.enabled(if: SiteStore.isSite(site)))
    func hiddenLeadingLinesComeBack() async throws {
        let schema = try await SchemaLoader.load(site: Self.site)
        let loaded = SiteStore.readAll(schema, site: Self.site)
        for entry in loaded.entries.values.flatMap({ $0 }) {
            guard let body = entry.body else { continue }
            let parts = await EntryEditor.splitLead(body)
            #expect(parts.lead + parts.text == body, "\(entry.id)")
            #expect(!parts.text.hasPrefix("\n"))
        }
    }

    /// Equal values, with dates compared by instant (a rewrite keeps the raw text anyway).
    static func same(_ a: FieldValue, _ b: FieldValue) -> Bool {
        switch (a, b) {
        case (.date(let x, _), .date(let y, _)): return x == y
        case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        case (.object(let x), .object(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && same($0.value, $1.value) }
        default: return a == b
        }
    }
}
