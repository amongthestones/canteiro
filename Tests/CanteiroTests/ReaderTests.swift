import Foundation
import Testing
@testable import Canteiro

@Suite struct ReaderTests {
    @Test func frontmatterKeepsBodyExactly() {
        let text = "---\ntitle: Hi\n---\n\nFirst line.\n"
        let parts = YAMLReader.splitFrontmatter(text)
        #expect(parts.yaml == "title: Hi")
        #expect(parts.body == "\nFirst line.\n")
    }

    @Test func noFrontmatterIsAllBody() {
        let parts = YAMLReader.splitFrontmatter("Just text.")
        #expect(parts.yaml.isEmpty)
        #expect(parts.body == "Just text.")
    }

    @Test func valuesKeepTypeAndOrder() throws {
        let value = try YAMLReader.parse("""
        title: "Some Values"
        draft: true
        part: 2
        date: 2026-09-28T23:10:00.000Z
        quoted: "2020-04-21T18:24:40"
        tags: ["life", "Galicia"]
        empty:
        """)
        guard case .object(let pairs) = value else { Issue.record("not an object"); return }
        #expect(pairs.map(\.key) == ["title", "draft", "part", "date", "quoted", "tags", "empty"])
        #expect(value["title"] == .string("Some Values"))
        #expect(value["draft"] == .bool(true))
        #expect(value["part"] == .int(2))
        if case .date(_, let raw) = value["date"] { #expect(raw == "2026-09-28T23:10:00.000Z") } else { Issue.record("date") }
        #expect(value["quoted"]?.date != nil)
        #expect(value["tags"] == .array([.string("life"), .string("Galicia")]))
        #expect(value["empty"] == .null)
    }

    @Test func jsonReadsAsYAML() throws {
        let value = try YAMLReader.parse(#"{"tags": ["A Coruña", "ADHD"], "explicit": false}"#)
        #expect(value["tags"]?.array?.count == 2)
        #expect(value["explicit"] == .bool(false))
    }

    @Test func settingAKeyKeepsItsPlace() throws {
        var value = try YAMLReader.parse("a: 1\nb: 2\nc: 3")
        value["b"] = .int(20)
        value["d"] = .int(4)
        guard case .object(let pairs) = value else { return }
        #expect(pairs.map(\.key) == ["a", "b", "c", "d"])
        #expect(value["b"] == .int(20))
    }
}
