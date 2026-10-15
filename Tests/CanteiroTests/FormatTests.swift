import Foundation
import Testing
@testable import Canteiro

@Suite struct FormatTests {
    /// Applies an edit and marks the selection after it with ‸ or «…».
    private func run(_ text: String, _ edit: (String, NSRange) -> MarkdownFormat.Edit?) -> String? {
        let (plain, selection) = parse(text)
        guard let e = edit(plain, selection) else { return nil }
        let out = (plain as NSString).replacingCharacters(in: e.range, with: e.text) as NSString
        if e.selection.length == 0 { return out.replacingCharacters(in: e.selection, with: "‸") }
        let inner = out.substring(with: e.selection)
        return out.replacingCharacters(in: e.selection, with: "«\(inner)»")
    }

    /// "a «b» c" selects b; "a ‸b" puts the caret before b.
    private func parse(_ text: String) -> (String, NSRange) {
        let ns = text as NSString
        let caret = ns.range(of: "‸")
        if caret.location != NSNotFound {
            return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let open = ns.range(of: "«"), close = ns.range(of: "»")
        let plain = text.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return (plain, NSRange(location: open.location, length: close.location - open.location - 1))
    }

    @Test func linkUsesTheURLOnTheClipboard() {
        let link = { (t: String, s: NSRange) in MarkdownFormat.link(t, s, clipboard: "https://ia.net/writer\n") }
        #expect(run("Read «iA Writer» now.", link) == "Read [iA Writer](https://ia.net/writer)‸ now.")
        #expect(run("Read ‸ now.", link) == "Read [‸](https://ia.net/writer) now.")
    }

    @Test func linkWithoutAURLLeavesTheCaretInTheParentheses() {
        let link = { (t: String, s: NSRange) in MarkdownFormat.link(t, s, clipboard: "just words") }
        #expect(run("Read «this».", link) == "Read [this](‸).")
    }

    @Test func aSelectedURLBecomesTheAddress() {
        let link = { (t: String, s: NSRange) in MarkdownFormat.link(t, s, clipboard: nil) }
        #expect(run("See «https://x.y/z» here", link) == "See [‸](https://x.y/z) here")
        let image = { (t: String, s: NSRange) in MarkdownFormat.link(t, s, clipboard: "https://x.y/a.jpg", image: true) }
        #expect(run("«A dog»", image) == "![A dog](https://x.y/a.jpg)‸")
    }

    @Test func wrapAddsAndRemovesMarks() {
        let bold = { (t: String, s: NSRange) in MarkdownFormat.wrap(t, s, with: "**") }
        let italic = { (t: String, s: NSRange) in MarkdownFormat.wrap(t, s, with: "*") }
        #expect(run("a «word » b", bold) == "a **«word»**  b")
        #expect(run("a **«word»** b", bold) == "a «word» b")
        #expect(run("a «**word**» b", bold) == "a «word» b")
        #expect(run("a wo‸rd b", italic) == "a *«word»* b")
        #expect(run("a ‸ b", italic) == "a *‸* b")
        // Italic inside bold adds a mark rather than eating one of bold's.
        #expect(run("a **«word»** b", italic) == "a ***«word»*** b")
        #expect(run("a ***«word»*** b", italic) == "a **«word»** b")
    }

    @Test func headingsAndListsToggle() {
        let h2 = { (t: String, s: NSRange) in MarkdownFormat.line(t, s, .heading(2)) }
        #expect(run("Ti‸tle\nnext", h2) == "## Ti‸tle\nnext")
        #expect(run("## Ti‸tle", h2) == "Ti‸tle")
        #expect(run("# Ti‸tle", h2) == "## Ti‸tle")
        let ordered = { (t: String, s: NSRange) in MarkdownFormat.line(t, s, .orderedList) }
        #expect(run("«one\n- two»\nthree", ordered) == "«1. one\n2. two»\nthree")
        #expect(run("«1. one\n2. two»", ordered) == "«one\ntwo»")
        let task = { (t: String, s: NSRange) in MarkdownFormat.line(t, s, .taskList) }
        #expect(run("  bu‸y milk", task) == "  - [ ] bu‸y milk")
    }

    @Test func tasksTick() {
        #expect(run("- [ ] mi‸lk", MarkdownFormat.toggleTask) == "- [x] mi‸lk")
        #expect(run("1. [x] mi‸lk", MarkdownFormat.toggleTask) == "1. [ ] mi‸lk")
        #expect(run("mi‸lk", MarkdownFormat.toggleTask) == nil)
    }

    @Test func codeBlockFencesLines() {
        #expect(run("a\nle‸t x\nb", MarkdownFormat.codeBlock) == "a\n```\n«let x»\n```\nb")
        #expect(run("«```\nlet x\n```»", MarkdownFormat.codeBlock) == "«let x»")
    }

    @Test func linesMove() {
        let up = { (t: String, s: NSRange) in MarkdownFormat.moveLines(t, s, up: true) }
        let down = { (t: String, s: NSRange) in MarkdownFormat.moveLines(t, s, up: false) }
        #expect(run("one\ntw‸o\nthree", up) == "tw‸o\none\nthree")
        #expect(run("one\ntw‸o\nthree", down) == "one\nthree\ntw‸o")
        #expect(run("o‸ne\ntwo", up) == nil)
        #expect(run("one\ntw‸o", down) == nil)
    }
}
