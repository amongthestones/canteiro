import Foundation
import Testing
@testable import Canteiro

/// Reads the real Among the Stones site, when it's on this Mac.
@Suite struct SiteTests {
    static let site = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Projects/among-the-stones")

    @Test(.enabled(if: SiteStore.isSite(site)))
    func readsEveryFile() async throws {
        let schema = try await SchemaLoader.load(site: Self.site)
        #expect(schema.groups.map(\.name) == ["Writing", "Tales", "Podcasts", "Site"])
        let loaded = SiteStore.readAll(schema, site: Self.site)
        #expect(loaded.problems.isEmpty, "\(loaded.problems)")
        #expect((loaded.entries["posts"]?.count ?? 0) > 200)
        #expect(loaded.entries["fiction"]?.contains { $0.slug == "books/moon-road/01" } == true)
        #expect(loaded.singletons["glossary"]?.data["terms"]?.array?.isEmpty == false)
        #expect(loaded.singletons["tags"]?.data["tags"]?.array?.isEmpty == false)
        // Every post with a date has one that parses.
        let undated = loaded.entries["posts"]?.filter { $0.data["date"] != nil && $0.data["date"]?.date == nil } ?? []
        #expect(undated.isEmpty, "\(undated.map(\.id))")
    }
}
