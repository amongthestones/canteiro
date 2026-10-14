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
        tags: ["life", "Travel"]
        empty:
        """)
        guard case .object(let pairs) = value else { Issue.record("not an object"); return }
        #expect(pairs.map(\.key) == ["title", "draft", "part", "date", "quoted", "tags", "empty"])
        #expect(value["title"] == .string("Some Values"))
        #expect(value["draft"] == .bool(true))
        #expect(value["part"] == .int(2))
        if case .date(_, let raw) = value["date"] { #expect(raw == "2026-09-28T23:10:00.000Z") } else { Issue.record("date") }
        #expect(value["quoted"]?.date != nil)
        #expect(value["tags"] == .array([.string("life"), .string("Travel")]))
        #expect(value["empty"] == .null)
    }

    @Test func jsonReadsAsYAML() throws {
        let value = try YAMLReader.parse(#"{"tags": ["São Paulo", "Health"], "explicit": false}"#)
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

    /// One file that won't parse is named in problems; the rest still load.
    @Test func aBadFileDoesNotHideTheRest() throws {
        let fm = FileManager.default
        // realpath, since the temporary folder is behind /var -> /private/var
        // and the loader's paths must start with the site's.
        let temp = URL(fileURLWithPath: String(cString: realpath(fm.temporaryDirectory.path, nil)))
        let site = temp.appending(path: "canteiro-reader-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: site) }
        let folder = site.appending(path: "src/content/posts")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\ntitle: Good\n---\n\nBody\n".write(to: folder.appending(path: "good.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: Bad\ndescription: Draft: not quoted\n---\n".write(to: folder.appending(path: "bad.md"), atomically: true, encoding: .utf8)
        let json = #"{"key":"posts","kind":"collection","label":"Posts","path":"src/content/posts/*","format":{"contentField":"content"},"fields":[{"key":"content","type":"markdoc","extension":"md"}]}"#
        let item = try JSONDecoder().decode(SchemaItem.self, from: Data(json.utf8))

        let read = ContentLoader.entries(of: item, in: site)
        #expect(read.entries.map(\.slug) == ["good"])
        #expect(read.problems.count == 1)
        #expect(read.problems.first?.hasPrefix("src/content/posts/bad.md") == true)
    }
}
