import Foundation
import Testing
@testable import Canteiro

/// Renaming an entry moves what Keystatic would and nothing else.
@Suite struct RenameTests {
    private func item(path: String, field: String) throws -> SchemaItem {
        let json = #"{"key":"posts","kind":"collection","label":"Posts","path":"\#(path)","format":"yaml","fields":[\#(field)]}"#
        return try JSONDecoder().decode(SchemaItem.self, from: Data(json.utf8))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "rename-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func slugsAreCleanedAndKeepTheirFolder() {
        #expect(Renamer.slug("Artificial Intelligence!", replacing: "ai") == "artificial-intelligence")
        #expect(Renamer.slug("Chapter Two", replacing: "moon-road/chapter-1") == "moon-road/chapter-two")
    }

    @Test func movesTheFileItsImagesAndThePathsToThem() throws {
        let item = try item(path: "src/content/posts/*",
                            field: #"{"key":"cover","type":"image","directory":"public/images/posts","publicPath":"/images/posts/"}"#)
        let site = try folder()
        let fm = FileManager.default
        try fm.createDirectory(at: site.appending(path: "src/content/posts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: site.appending(path: "public/images/posts/ai"), withIntermediateDirectories: true)
        try "title: AI\ncover: /images/posts/ai/cover.jpg\n".write(to: site.appending(path: "src/content/posts/ai.yaml"), atomically: true, encoding: .utf8)
        try Data().write(to: site.appending(path: "public/images/posts/ai/cover.jpg"))

        let plan = Renamer.plan(site: site, item: item, from: "ai", to: "machines")
        try Renamer.apply(plan, site: site, entry: "src/content/posts/machines.yaml")

        #expect(!fm.fileExists(atPath: site.appending(path: "src/content/posts/ai.yaml").path))
        #expect(fm.fileExists(atPath: site.appending(path: "public/images/posts/machines/cover.jpg").path))
        let text = try String(contentsOf: site.appending(path: "src/content/posts/machines.yaml"), encoding: .utf8)
        #expect(text == "title: AI\ncover: /images/posts/machines/cover.jpg\n")
    }

    @Test func aTakenNameStopsBeforeAnythingMoves() throws {
        let item = try item(path: "src/content/posts/*", field: #"{"key":"title","type":"text"}"#)
        let site = try folder()
        try FileManager.default.createDirectory(at: site.appending(path: "src/content/posts"), withIntermediateDirectories: true)
        for name in ["ai", "machines"] {
            try "title: x\n".write(to: site.appending(path: "src/content/posts/\(name).yaml"), atomically: true, encoding: .utf8)
        }
        #expect(throws: Renamer.Failure.self) {
            try Renamer.apply(Renamer.plan(site: site, item: item, from: "ai", to: "machines"), site: site, entry: "src/content/posts/machines.yaml")
        }
        #expect(FileManager.default.fileExists(atPath: site.appending(path: "src/content/posts/ai.yaml").path))
    }

    @Test func aFolderPerEntryMovesTheFolder() throws {
        let item = try item(path: "src/content/books/*/index", field: #"{"key":"title","type":"text"}"#)
        let plan = Renamer.plan(site: URL(fileURLWithPath: "/site"), item: item, from: "moon", to: "sun")
        #expect(plan.moves == [.init(from: "src/content/books/moon", to: "src/content/books/sun")])
    }

    @Test func redirectsGoStraightToTheNewAddress() throws {
        let file = try folder().appending(path: "_redirects")
        try "# Old\n/2019/ai/  /posts/ai/  301\n/posts/  /category/posts/  301\n".write(to: file, atomically: true, encoding: .utf8)
        try Renamer.redirect(file, from: "/posts/ai/", to: "/posts/machines/")
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        #expect(lines.contains("/2019/ai/  /posts/machines/  301"), "no chain through the old address")
        #expect(lines.contains("/posts/  /category/posts/  301"))
        #expect(lines.suffix(3) == ["# Renamed in Canteiro", "/posts/ai/  /posts/machines/  301", ""])
    }
}
