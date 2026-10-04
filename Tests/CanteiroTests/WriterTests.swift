import Foundation
import Testing
@testable import Canteiro

@Suite struct WriterTests {
    private func entry(_ raw: String, body: Bool) throws -> Entry {
        let parts = body ? YAMLReader.splitFrontmatter(raw) : (raw, nil)
        return Entry(id: "x", slug: "x", url: URL(fileURLWithPath: "/x"),
                     data: try YAMLReader.parse(parts.0), body: parts.1, raw: raw)
    }

    private let frontmatter = Format.frontmatter

    @Test func unchangedWritesNothing() throws {
        let e = try entry("---\ntitle: Hi\n---\nText\n", body: true)
        #expect(FileWriter.text(for: e, data: e.data, body: e.body, format: frontmatter) == nil)
    }

    @Test func bodyEditKeepsFrontmatterExactly() throws {
        let raw = "---\ntitle: \"Some Values\"\ncategories: [\"posts\"]\n# a comment\n---\n\nOld text.\n"
        let e = try entry(raw, body: true)
        let out = FileWriter.text(for: e, data: e.data, body: "\nNew text.\n", format: frontmatter)
        #expect(out == "---\ntitle: \"Some Values\"\ncategories: [\"posts\"]\n# a comment\n---\n\nNew text.\n")
    }

    @Test func oneFieldChangesOnlyItsLines() throws {
        let raw = "---\ntitle: \"Some Values\"\ndraft: false\ntags: [\"life\"]\n---\nBody\n"
        let e = try entry(raw, body: true)
        var data = e.data
        data["draft"] = .bool(true)
        let out = FileWriter.text(for: e, data: data, body: e.body, format: frontmatter)
        #expect(out == "---\ntitle: \"Some Values\"\ndraft: true\ntags: [\"life\"]\n---\nBody\n")
    }

    @Test func listsAndNewKeysInKeystaticStyle() throws {
        let raw = "title: Glossary\n"
        let e = try entry(raw, body: false)
        var data = e.data
        data["terms"] = .array([.object([FieldPair(key: "term", value: .string("Duna")),
                                         FieldPair(key: "meaning", value: .string("Life-force: it pools."))])])
        data["tags"] = .array([.string("A Coruña"), .string("true")])
        let out = FileWriter.text(for: e, data: data, body: nil, format: Format(data: "yaml"))
        #expect(out == """
        title: Glossary
        terms:
          - term: Duna
            meaning: "Life-force: it pools."
        tags:
          - A Coruña
          - "true"

        """)
    }

    @Test func multilineStringsBecomeBlocks() throws {
        let e = try entry("text: one\n", body: false)
        var data = e.data
        data["text"] = .string("Line one\nLine two")
        let out = FileWriter.text(for: e, data: data, body: nil, format: Format(data: "yaml"))
        #expect(out == "text: |-\n  Line one\n  Line two\n")
        #expect(try YAMLReader.parse(out!)["text"] == .string("Line one\nLine two"))
    }

    @Test func quotingRules() {
        for s in ["", " pad", "true", "No", "null", "12", "3.5", "2026-09-28", "- dash", "a: b", "#hash", "x #y", "'q"] {
            #expect(YAMLEmitter.needsQuotes(s), "\(s)")
        }
        for s in ["2026-10-04-1032", "Moon Road", "Ash Season", "The Stranger's Gun", "A Coruña", "/tales/", "http://x.y/z"] {
            #expect(!YAMLEmitter.needsQuotes(s), "\(s)")
        }
    }
}

extension Format {
    static var frontmatter: Format { Format(data: "yaml", contentField: "content") }
}
