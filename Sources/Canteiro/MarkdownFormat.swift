import Foundation

/// The Format menu's edits, as in iA Writer: each takes the text and the
/// selection and returns one replacement, or nil when there's nothing to do.
/// Ranges are UTF-16, as NSTextView counts them.
enum MarkdownFormat {
    struct Edit: Equatable {
        var range: NSRange
        var text: String
        /// The selection after the edit.
        var selection: NSRange
    }

    enum Line: Equatable {
        case heading(Int)
        case orderedList
        case taskList
        case orderedTaskList
    }

    // MARK: Inline

    /// Wraps the selection in a mark (`**`, `*`, `~~`, `==`, `` ` ``), or takes
    /// the mark off when it's already there. With nothing selected, it wraps
    /// the word at the caret, or puts down an empty pair to type into.
    static func wrap(_ text: String, _ selection: NSRange, with mark: String) -> Edit? {
        let ns = text as NSString
        let m = (mark as NSString).length
        var sel = trimmed(selection, in: ns)
        if sel.length == 0 { sel = word(at: sel.location, in: ns) }
        let inner = ns.substring(with: sel)

        // The marks are selected along with the text.
        if sel.length >= 2 * m, inner.hasPrefix(mark), inner.hasSuffix(mark) {
            let bare = String(inner.dropFirst(mark.count).dropLast(mark.count))
            return Edit(range: sel, text: bare, selection: NSRange(location: sel.location, length: sel.length - 2 * m))
        }
        // The marks sit just outside the selection.
        if sel.length > 0, has(mark, before: sel.location, in: ns), has(mark, after: NSMaxRange(sel), in: ns) {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            return Edit(range: outer, text: inner, selection: NSRange(location: outer.location, length: sel.length))
        }
        return Edit(range: sel, text: mark + inner + mark, selection: NSRange(location: sel.location + m, length: sel.length))
    }

    /// `[text](url)` with the URL on the clipboard, or `[text]()` with the
    /// caret in the parentheses to type or paste one. A selected URL becomes
    /// the link's address, with the caret in the brackets for its text.
    static func link(_ text: String, _ selection: NSRange, clipboard: String?, image: Bool = false) -> Edit? {
        let ns = text as NSString
        let sel = trimmed(selection, in: ns)
        let selected = ns.substring(with: sel)
        let open = image ? "![" : "["
        let o = (open as NSString).length

        if let url = address(selected) {
            return Edit(range: sel, text: "\(open)](\(url))", selection: NSRange(location: sel.location + o, length: 0))
        }
        if let url = clipboard.flatMap(address) {
            let link = "\(open)\(selected)](\(url))"
            let caret = sel.length == 0 ? sel.location + o : sel.location + (link as NSString).length
            return Edit(range: sel, text: link, selection: NSRange(location: caret, length: 0))
        }
        return Edit(range: sel, text: "\(open)\(selected)]()",
                    selection: NSRange(location: sel.location + o + sel.length + 2, length: 0))
    }

    /// `[^text]`, an inline footnote.
    static func footnote(_ text: String, _ selection: NSRange) -> Edit? {
        let sel = trimmed(selection, in: text as NSString)
        let note = (text as NSString).substring(with: sel)
        let caret = sel.length == 0 ? sel.location + 2 : sel.location + (note as NSString).length + 3
        return Edit(range: sel, text: "[^\(note)]", selection: NSRange(location: caret, length: 0))
    }

    // MARK: Lines

    /// Makes the selected lines a heading or a list, or plain again when
    /// they already are that.
    static func line(_ text: String, _ selection: NSRange, _ kind: Line) -> Edit? {
        let ns = text as NSString
        let block = lineBlock(selection, in: ns)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !filled.isEmpty else {
            let start = prefix(kind, number: 1)
            return Edit(range: NSRange(location: selection.location, length: 0), text: start,
                        selection: NSRange(location: selection.location + (start as NSString).length, length: 0))
        }
        let already = filled.allSatisfy { split($0).kind == kind }
        var number = 0
        let changed = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let (indent, _, body) = split(line)
            if already { return indent + body }
            number += 1
            // Headings don't nest.
            return (kind.isHeading ? "" : indent) + prefix(kind, number: number) + body
        }.joined(separator: "\n")

        let grown = (changed as NSString).length - block.length
        let after: NSRange
        if selection.length == 0, lines.count == 1 {
            // The caret keeps its place in the words.
            let fromEnd = NSMaxRange(block) - selection.location
            after = NSRange(location: max(block.location, block.location + block.length + grown - fromEnd), length: 0)
        } else {
            after = NSRange(location: block.location, length: (changed as NSString).length)
        }
        return Edit(range: block, text: changed, selection: after)
    }

    /// Ticks or unticks the tasks on the selected lines.
    static func toggleTask(_ text: String, _ selection: NSRange) -> Edit? {
        let ns = text as NSString
        let block = lineBlock(selection, in: ns)
        var found = false
        let changed = ns.substring(with: block).components(separatedBy: "\n").map { line -> String in
            guard let box = line.range(of: #"^[ \t]*(?:[-*+]|\d+\.)[ \t]+\[[ xX]\]"#, options: .regularExpression) else { return line }
            found = true
            let tick = line.index(box.upperBound, offsetBy: -2)
            let done = line[tick] != " "
            return line.replacingCharacters(in: tick...tick, with: done ? " " : "x")
        }.joined(separator: "\n")
        guard found else { return nil }
        return Edit(range: block, text: changed, selection: selection)
    }

    /// Fences the selected lines as a code block, or takes the fences off.
    static func codeBlock(_ text: String, _ selection: NSRange) -> Edit? {
        let ns = text as NSString
        let block = lineBlock(selection, in: ns)
        let body = ns.substring(with: block)
        var lines = body.components(separatedBy: "\n")
        if lines.count >= 2, lines.first!.hasPrefix("```"), lines.last!.hasPrefix("```") {
            lines.removeFirst()
            lines.removeLast()
            let bare = lines.joined(separator: "\n")
            return Edit(range: block, text: bare, selection: NSRange(location: block.location, length: (bare as NSString).length))
        }
        let fenced = "```\n" + body + "\n```"
        let caret = body.isEmpty
            ? NSRange(location: block.location + 4, length: 0)
            : NSRange(location: block.location + 4, length: block.length)
        return Edit(range: block, text: fenced, selection: caret)
    }

    /// Swaps the selected lines with the line above or below.
    static func moveLines(_ text: String, _ selection: NSRange, up: Bool) -> Edit? {
        let ns = text as NSString
        let block = lineBlock(selection, in: ns)
        if up {
            guard block.location > 0 else { return nil }
            let above = lineBlock(NSRange(location: block.location - 1, length: 0), in: ns)
            let moved = ns.substring(with: block) + "\n" + ns.substring(with: above)
            let union = NSRange(location: above.location, length: NSMaxRange(block) - above.location)
            return Edit(range: union, text: moved,
                        selection: NSRange(location: selection.location - above.length - 1, length: selection.length))
        }
        guard NSMaxRange(block) < ns.length else { return nil }
        let below = lineBlock(NSRange(location: NSMaxRange(block) + 1, length: 0), in: ns)
        let moved = ns.substring(with: below) + "\n" + ns.substring(with: block)
        let union = NSRange(location: block.location, length: NSMaxRange(below) - block.location)
        return Edit(range: union, text: moved,
                    selection: NSRange(location: selection.location + below.length + 1, length: selection.length))
    }

    // MARK: Helpers

    /// The whole lines the selection touches, without the last line break.
    /// A selection that ends at the start of a line leaves that line out.
    static func lineBlock(_ selection: NSRange, in ns: NSString) -> NSRange {
        var end = NSMaxRange(selection)
        if selection.length > 0, end > 0, ns.character(at: end - 1) == 10 { end -= 1 }
        let start = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        var stop = ns.lineRange(for: NSRange(location: end, length: 0))
        if NSMaxRange(stop) > 0, NSMaxRange(stop) <= ns.length, NSMaxRange(stop) > stop.location,
           ns.character(at: NSMaxRange(stop) - 1) == 10 {
            stop.length -= 1
        }
        return NSRange(location: start, length: max(0, NSMaxRange(stop) - start))
    }

    private static func prefix(_ kind: Line, number: Int) -> String {
        switch kind {
        case .heading(let level): String(repeating: "#", count: level) + " "
        case .orderedList: "\(number). "
        case .taskList: "- [ ] "
        case .orderedTaskList: "\(number). [ ] "
        }
    }

    /// A line's indent, what kind of line it is, and its words.
    private static func split(_ line: String) -> (indent: String, kind: Line?, body: String) {
        let patterns: [(String, (Substring) -> Line?)] = [
            (#"^#{1,6}[ \t]+"#, { .heading($0.filter { $0 == "#" }.count) }),
            (#"^[ \t]*\d+\.[ \t]+\[[ xX]\][ \t]+"#, { _ in .orderedTaskList }),
            (#"^[ \t]*[-*+][ \t]+\[[ xX]\][ \t]+"#, { _ in .taskList }),
            (#"^[ \t]*\d+\.[ \t]+"#, { _ in .orderedList }),
            // A plain bullet is swapped for the new prefix, never kept.
            (#"^[ \t]*[-*+][ \t]+"#, { _ in nil }),
        ]
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        for (pattern, kind) in patterns {
            if let r = line.range(of: pattern, options: .regularExpression) {
                return (indent, kind(line[r]), String(line[r.upperBound...]))
            }
        }
        return (indent, nil, String(line.dropFirst(indent.count)))
    }

    /// The selection without spaces at its ends, as a double-click can take.
    private static func trimmed(_ selection: NSRange, in ns: NSString) -> NSRange {
        var start = selection.location, end = NSMaxRange(selection)
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func word(at index: Int, in ns: NSString) -> NSRange {
        var start = index, end = index
        while start > 0, isWord(ns.character(at: start - 1)) { start -= 1 }
        while end < ns.length, isWord(ns.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Whether the mark sits right before or after a position. A single `*`
    /// next to `**` is bold, not italic, so runs of the mark's character
    /// are counted: odd for `*`, two or more for `**`.
    private static func has(_ mark: String, before index: Int, in ns: NSString) -> Bool {
        run(of: mark, from: index, step: -1, in: ns)
    }

    private static func has(_ mark: String, after index: Int, in ns: NSString) -> Bool {
        run(of: mark, from: index, step: 1, in: ns)
    }

    private static func run(of mark: String, from index: Int, step: Int, in ns: NSString) -> Bool {
        let unit = (mark as NSString).character(at: 0)
        let uniform = mark.utf16.allSatisfy { $0 == unit }
        let m = (mark as NSString).length
        guard uniform else {
            let range = step < 0 ? NSRange(location: index - m, length: m) : NSRange(location: index, length: m)
            return range.location >= 0 && NSMaxRange(range) <= ns.length && ns.substring(with: range) == mark
        }
        var count = 0, k = step < 0 ? index - 1 : index
        while k >= 0, k < ns.length, ns.character(at: k) == unit { count += 1; k += step }
        if mark == "*" { return count % 2 == 1 }
        return count >= m
    }

    private static func address(_ string: String) -> String? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace),
              let scheme = URL(string: s)?.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return s
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 }

    private static func isWord(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || c == 39 || c == 0x2019
    }
}

private extension MarkdownFormat.Line {
    var isHeading: Bool { if case .heading = self { true } else { false } }
}
