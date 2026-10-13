import Foundation
import Testing
@testable import Canteiro

/// Reads a real Keystatic site: the one CANTEIRO_TEST_SITE points to.
/// Skipped when it isn't set.
@Suite struct SiteTests {
    static let site: URL = {
        let path = ProcessInfo.processInfo.environment["CANTEIRO_TEST_SITE"] ?? ""
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }()

    static var hasSite: Bool {
        ProcessInfo.processInfo.environment["CANTEIRO_TEST_SITE"] != nil && SiteStore.isSite(site)
    }

    @Test(.enabled(if: hasSite))
    func readsEveryFile() async throws {
        let schema = try await SchemaLoader.load(site: Self.site)
        #expect(!schema.items.isEmpty)
        #expect(schema.groups.flatMap(\.items).count == schema.items.count, "every item is in the sidebar once")
        let loaded = SiteStore.readAll(schema, site: Self.site)
        #expect(loaded.problems.isEmpty, "\(loaded.problems)")
        // Every entry with a date has one that parses.
        for item in schema.items where item.kind == .collection {
            guard let field = item.dateField else { continue }
            let undated = loaded.entries[item.key]?.filter { $0.data[field.key] != nil && $0.data[field.key]?.date == nil } ?? []
            #expect(undated.isEmpty, "\(undated.map(\.id))")
        }
    }

    /// Every file on the site: splicing unchanged data rebuilds it byte for
    /// byte, a fresh rewrite of every field reads back the same, and JSON
    /// matches Keystatic's own output.
    @Test(.enabled(if: hasSite))
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
        #expect(checked > 0)
    }

    /// The editor hides blank lines at the top of a body; putting them back
    /// gives every body on the site back exactly.
    @Test(.enabled(if: hasSite))
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
