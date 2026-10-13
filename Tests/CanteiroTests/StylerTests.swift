import AppKit
import Testing
@testable import Canteiro

@MainActor
@Suite struct StylerTests {
    private let text = "## Better Footnotes\n==I like highlighting.== A note[^iA numbers these.] and a [link](https://x.y).\n^^^A callout.^^^\n"

    private func styled(_ mode: BodyMode) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.style(storage, mode: mode, syntax: Set(SiteConfig.Syntax.allCases))
        return storage
    }

    private func at(_ storage: NSTextStorage, _ needle: String, offset: Int = 0) -> [NSAttributedString.Key: Any] {
        let range = (storage.string as NSString).range(of: needle)
        return storage.attributes(at: range.location + offset, effectiveRange: nil)
    }

    private func hidden(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        (attrs[.foregroundColor] as? NSColor) == .clear
    }

    @Test func richHidesTheMarksAndShowsTheResult() {
        let s = styled(.rich)
        #expect(s.string == text, "styling never changes the text")
        #expect(hidden(at(s, "## ")))
        #expect((at(s, "Better")[.font] as? NSFont)?.pointSize == 21)
        #expect(hidden(at(s, "==I")))
        #expect(at(s, "I like")[.backgroundColor] != nil)
        #expect(hidden(at(s, "[^")))
        #expect((at(s, "iA numbers")[.baselineOffset] as? Int) == 5)
        #expect(hidden(at(s, "](https")))
        #expect((at(s, "link")[.foregroundColor] as? NSColor) == .linkColor)
        #expect(hidden(at(s, "^^^A")))
        #expect(at(s, "A callout")[.backgroundColor] != nil)
    }

    @Test func markdownFadesTheMarks() {
        let s = styled(.markdown)
        #expect((at(s, "## ")[.foregroundColor] as? NSColor) == .tertiaryLabelColor)
        #expect((at(s, "==I")[.foregroundColor] as? NSColor) == .tertiaryLabelColor)
        #expect(at(s, "I like")[.backgroundColor] != nil)
        #expect((at(s, "Better")[.font] as? NSFont)?.isFixedPitch == true)
    }

    private let table = "Intro.\n\n| Account | Handle |\n|---|---|\n| Instagram | [@amongthestones](https://instagram.com/amongthestones) |\n| LinkedIn | [jmbaum](https://www.linkedin.com/in/jmbaum/) |\n\n*Checked.*\n"

    @Test func findsTheTableAndItsCells() {
        let tables = MarkdownStyler.tables(in: table as NSString)
        #expect(tables.count == 1)
        #expect(tables[0].rows.count == 3)
        let cells = tables[0].rows[1].cells.map { (table as NSString).substring(with: $0) }
        #expect(cells == ["Instagram", "[@amongthestones](https://instagram.com/amongthestones)"])
        let escaped = "a | \\| b" as NSString
        #expect(MarkdownStyler.cells(in: NSRange(location: 0, length: escaped.length), of: escaped).count == 2,
                "an escaped pipe stays in its cell")
    }

    @Test func richLinesTheColumnsUp() {
        let s = NSTextStorage(string: table)
        MarkdownStyler.style(s, mode: .rich)
        #expect(s.string == table, "styling never changes the text")
        #expect(hidden(at(s, "| Account")))
        #expect(hidden(at(s, "|---")))
        #expect((at(s, "Account")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        // Where the second column starts, row by row.
        func start(_ row: String, _ cell: String) -> CGFloat {
            let text = s.string as NSString
            let line = text.range(of: row)
            let cellAt = text.range(of: cell, range: NSRange(location: line.location, length: text.length - line.location)).location
            return s.attributedSubstring(from: NSRange(location: line.location, length: cellAt - line.location)).size().width
        }
        let header = start("| Account", "Handle")
        #expect(abs(start("| Instagram", "[@among") - header) < 0.5)
        #expect(abs(start("| LinkedIn", "[jmbaum") - header) < 0.5)
    }

    @Test func markdownFadesTheTablePipes() {
        let s = NSTextStorage(string: table)
        MarkdownStyler.style(s, mode: .markdown)
        #expect((at(s, "| Account")[.foregroundColor] as? NSColor) == .tertiaryLabelColor)
        #expect((at(s, "|---")[.foregroundColor] as? NSColor) == .tertiaryLabelColor)
        #expect((at(s, "Account")[.foregroundColor] as? NSColor) == .labelColor)
        #expect(at(s, "| Instagram", offset: 11)[.kern] == nil, "the mono view keeps its own spacing")
    }

    @Test func richAlignsColumnsFromTheColons() {
        let text = "| Item | Count | Note |\n|:---|---:|:---:|\n| Apples | 3 | ok |\n| Pears | 120 | fine |\n"
        let s = NSTextStorage(string: text)
        MarkdownStyler.style(s, mode: .rich)
        #expect(MarkdownStyler.alignments(MarkdownStyler.tables(in: text as NSString)[0], in: text as NSString) == [.left, .right, .center])
        // Where a cell ends, from the start of its line.
        func end(_ row: String, _ cell: String) -> CGFloat {
            let t = s.string as NSString
            let line = t.range(of: row), at = t.range(of: cell, range: NSRange(location: line.location, length: t.length - line.location))
            return s.attributedSubstring(from: NSRange(location: line.location, length: NSMaxRange(at) - line.location)).size().width
        }
        #expect(abs(end("| Apples", " 3") - end("| Pears", "120")) < 0.5, "right-aligned cells end together")
        #expect(abs(end("| Apples", "ok") - end("| Pears", "fine")) > 1, "centered cells don't")
    }

    @Test func onlyRichTagsTheGrid() {
        let rich = NSTextStorage(string: table), plain = NSTextStorage(string: table)
        MarkdownStyler.style(rich, mode: .rich)
        MarkdownStyler.style(plain, mode: .markdown)
        let header = at(rich, "Account")[.tableGrid] as? TableGrid
        #expect(header?.header == true)
        #expect(header?.lines.count == 1)
        #expect(at(rich, "|---")[.tableGrid] as? TableGrid === header, "the divider joins the header's cell")
        #expect((at(rich, "Instagram")[.tableGrid] as? TableGrid)?.header == false)
        #expect(at(rich, "Intro")[.tableGrid] == nil)
        #expect(at(plain, "Account")[.tableGrid] == nil)
    }
}
