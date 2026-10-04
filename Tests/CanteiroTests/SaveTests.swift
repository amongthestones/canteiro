import Foundation
import Testing
@testable import Canteiro

/// Saves into a scratch copy of the real site, never the site itself.
@MainActor
@Suite struct SaveTests {
    nonisolated static let site = SiteTests.site

    /// The site's config and content in a temp folder, sharing its node_modules.
    private func scratchSite() throws -> URL {
        let fm = FileManager.default
        let copy = fm.temporaryDirectory.appending(path: "canteiro-test-\(UUID().uuidString)")
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        for name in ["keystatic.config.ts", "package.json", "src"] {
            try fm.copyItem(at: Self.site.appending(path: name), to: copy.appending(path: name))
        }
        try fm.createSymbolicLink(at: copy.appending(path: "node_modules"), withDestinationURL: Self.site.appending(path: "node_modules"))
        return copy
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func savingChangesOnlyTheEditedLine() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        let entry = try #require(store.entries["posts"]?.first { $0.data["draft"]?.bool == true })

        var data = entry.data
        data["draft"] = .bool(false)
        store.save(item, id: entry.id, data: data, body: entry.body)

        let after = try String(contentsOf: entry.url, encoding: .utf8)
        let before = entry.raw.components(separatedBy: "\n")
        let now = after.components(separatedBy: "\n")
        #expect(before.count == now.count)
        let changed = zip(before, now).filter { $0 != $1 }
        #expect(changed.count == 1, "\(changed)")
        #expect(changed.first?.1 == "draft: false")
        #expect(store.current(item, id: entry.id)?.data["draft"] == .bool(false))
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aChangeOnDiskIsNeverWrittenOver() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        let entry = try #require(store.entries["posts"]?.first)

        let elsewhere = entry.raw + "\nAdded in iA Writer.\n"
        try elsewhere.write(to: entry.url, atomically: true, encoding: .utf8)
        store.save(item, id: entry.id, data: entry.data, body: (entry.body ?? "") + "Typed in Canteiro.")

        #expect(store.conflicts.contains(entry.id))
        #expect(try String(contentsOf: entry.url, encoding: .utf8) == elsewhere)

        store.reread(item, id: entry.id)
        #expect(!store.conflicts.contains(entry.id))
        #expect(store.current(item, id: entry.id)?.raw == elsewhere)
    }
}
