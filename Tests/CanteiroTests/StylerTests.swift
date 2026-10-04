import AppKit
import Testing
@testable import Canteiro

@MainActor
@Suite struct StylerTests {
    private let text = "## Better Footnotes\n==I like highlighting.== A note[^iA numbers these.] and a [link](https://x.y).\n^^^A callout.^^^\n"

    private func styled(_ mode: BodyMode) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.style(storage, mode: mode)
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
}
