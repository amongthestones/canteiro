import Foundation
import Testing
@testable import Canteiro

@Suite struct InboxTests {
    @Test func titleFromTheFirstHeading() {
        let parsed = DraftInbox.parse("# Walking to the river\n\nThe road was quiet.\n", name: "Untitled")
        #expect(parsed.title == "Walking to the river")
        #expect(parsed.body == "The road was quiet.\n", "the heading leaves the body; the post shows its title")
        #expect(parsed.fields.isEmpty)
    }

    @Test func titleFromTheFileName() {
        let parsed = DraftInbox.parse("\n\nJust text, no heading.\n", name: "Rain notes")
        #expect(parsed.title == "Rain notes")
        #expect(parsed.body == "Just text, no heading.\n")
    }

    @Test func frontmatterComesAlong() {
        let parsed = DraftInbox.parse("---\ntitle: From YAML\ntags:\n  - travel\n---\n# A heading\n\nBody.\n", name: "x")
        #expect(parsed.title == "From YAML", "frontmatter's title wins over the heading")
        #expect(parsed.fields.map(\.key) == ["tags"])
        #expect(parsed.body == "Body.\n")
    }

    @Test func aHeadingLaterOnStays() {
        let parsed = DraftInbox.parse("Opening line.\n\n# Later\n", name: "Notes")
        #expect(parsed.title == "Notes")
        #expect(parsed.body.contains("# Later"))
    }

    @MainActor @Test func savesAndNeverWritesOverIAWriter() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "# Rain\n\nFirst.\n".write(to: folder.appending(path: "Rain.md"), atomically: true, encoding: .utf8)

        let inbox = DraftInbox(folder: folder)
        #expect(inbox.drafts.map(\.title) == ["Rain"])
        // As the list has it, the way the editor gets it.
        let file = try #require(inbox.drafts.first?.url)
        #expect(inbox.selected == file)

        let text = inbox.open(file)
        inbox.edit(file, text + "Second.\n")
        inbox.save(file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Rain\n\nFirst.\nSecond.\n")
        #expect(!inbox.hasUnsaved(file))

        // The phone saves, then an edit here: kept back, not written over.
        try "# Rain\n\nFrom the phone.\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(inbox.changedOnDisk(file))
        inbox.edit(file, "# Rain\n\nFrom the Mac.\n")
        inbox.save(file)
        #expect(inbox.conflicts.contains(file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Rain\n\nFrom the phone.\n")

        inbox.save(file, overwrite: true)
        #expect(!inbox.conflicts.contains(file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Rain\n\nFrom the Mac.\n")
    }
}
