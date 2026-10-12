import Foundation
import Testing
@testable import Canteiro

@Suite struct ListFilterTests {
    static func entry(_ pairs: [(String, FieldValue)]) -> Entry {
        Entry(id: "x", slug: "x", url: URL(fileURLWithPath: "/x"),
              data: .object(pairs.map { FieldPair(key: $0.0, value: $0.1) }), body: nil, raw: "")
    }

    let draftNote = entry([("draft", .bool(true)), ("categories", .array([.string("notes")])), ("language", .string("gl"))])
    let post = entry([("categories", .array([.string("posts")])), ("language", .string("en"))])

    @Test func status() {
        var filter = ListFilter()
        #expect(filter.matches(draftNote) && filter.matches(post))
        filter.status = .drafts
        #expect(filter.matches(draftNote) && !filter.matches(post))
        filter.status = .published
        #expect(!filter.matches(draftNote) && filter.matches(post))
    }

    /// A select matches its value; a multiselect matches if the list has it.
    @Test func choices() {
        var filter = ListFilter()
        filter.choices["categories"] = "notes"
        #expect(filter.matches(draftNote) && !filter.matches(post))
        filter.choices = ["language": "en"]
        #expect(!filter.matches(draftNote) && filter.matches(post))
        filter.choices = ["language": "en", "categories": "notes"]
        #expect(!filter.matches(draftNote) && !filter.matches(post))
    }
}
