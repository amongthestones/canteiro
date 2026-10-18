import Foundation
import Testing
@testable import Canteiro

@Suite struct ListSortTests {
    private func item(_ fields: String) throws -> SchemaItem {
        let json = #"{"key":"k","kind":"collection","label":"K","path":"src/content/k/*","format":"yaml","slugField":"title","fields":[\#(fields)]}"#
        return try JSONDecoder().decode(SchemaItem.self, from: Data(json.utf8))
    }

    private let titleOnly = #"{"key":"title","type":"slug","label":"Title"}"#

    /// A file in a fresh folder, with its dates set by hand.
    private func entry(_ title: String, in folder: URL, edited: Date, added: Date) throws -> Entry {
        let url = folder.appendingPathComponent("\(title).yaml")
        try "title: \(title)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: edited, .creationDate: added], ofItemAtPath: url.path)
        return Entry(id: title, slug: title, url: url,
                     data: .object([FieldPair(key: "title", value: .string(title))]), body: nil, raw: "")
    }

    @Test func fileDatesOrderNewestFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let day: TimeInterval = 86_400
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try entry("a", in: folder, edited: old + 3 * day, added: old)
        let b = try entry("b", in: folder, edited: old + day, added: old + 2 * day)
        let c = try entry("c", in: folder, edited: old + 2 * day, added: old + day)
        let item = try item(titleOnly)

        #expect(ListSort.edited.apply([a, b, c], item: item).map(\.slug) == ["a", "c", "b"])
        #expect(ListSort.added.apply([a, b, c], item: item).map(\.slug) == ["b", "c", "a"])
        #expect(ListSort.standard.apply([c, a, b], item: item).map(\.slug) == ["c", "a", "b"])
        #expect(ListSort.edited.fileDate(a) == old + 3 * day)
        #expect(ListSort.title.fileDate(a) == nil)
    }

    /// Title isn't offered twice when the standard order is already by title.
    @Test func options() throws {
        let plain = try item(titleOnly)
        #expect(ListSort.options(for: plain) == [.standard, .edited, .added])
        #expect(ListSort.standard.label(for: plain) == "Title")

        let dated = try item(titleOnly + #",{"key":"date","type":"date","label":"Date"}"#)
        #expect(ListSort.options(for: dated) == [.standard, .edited, .added, .title])
        #expect(ListSort.standard.label(for: dated) == "Date")
    }
}
