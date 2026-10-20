import AppKit

/// How the entry is shown. Markdown and Read edit the same text; Read only
/// draws it differently, so the file on disk is exactly what was typed
/// either way.
enum BodyMode: String {
    case markdown, read
}

/// Styles the body's markdown in place. Markdown: a mono font with the marks
/// faded, as iA Writer does. Read: a reading font with the marks hidden and
/// the result shown. A site's own syntax, from its canteiro.json, comes on
/// top: ==highlights==, [^inline footnotes], ^^^callouts^^^ and {{TOC}}.
enum MarkdownStyler {
    static func style(_ storage: NSTextStorage, mode: BodyMode, syntax: Set<SiteConfig.Syntax> = [], look: ReadLook = .standard,
                      images: [String: NSSize] = [:]) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let read = mode == .read
        let base = baseFont(mode, look)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(mode, look), range: all)

        func each(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines], _ body: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: storage.string, range: all) { match, _, _ in if let match { body(match) } }
        }
        func mark(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            if read {
                // Tiny enough that a long hidden URL leaves no gap.
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear], range: range)
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }
        }
        func trait(_ range: NSRange, _ trait: NSFontTraitMask) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let font = value as? NSFont ?? base
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
            }
        }

        // Headings: # to ######.
        each(#"^(#{1,6})([ \t]+)(.+)$"#) { m in
            let level = m.range(at: 1).length
            let font = read ? look.headingFont(level: level) : NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
            storage.addAttribute(.font, value: font, range: m.range(at: 3))
            if read {
                storage.addAttribute(.foregroundColor, value: look.headings, range: m.range(at: 3))
                // A heading takes its own font's height, not the body's.
                if look.lineHeight != nil {
                    let style = NSMutableParagraphStyle()
                    style.lineSpacing = 4
                    storage.addAttribute(.paragraphStyle, value: style, range: m.range)
                }
            }
            mark(NSRange(location: m.range(at: 1).location, length: m.range(at: 1).length + m.range(at: 2).length))
        }
        // Bold, then italic.
        each(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#) { m in
            trait(m.range(at: 2), .boldFontMask)
            mark(NSRange(location: m.range.location, length: 2))
            mark(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(#"(?<![*\w])([*_])(?![*_\s])([^*_\n]+?)(?<=\S)\1(?![*\w])"#) { m in
            trait(m.range(at: 2), .italicFontMask)
            mark(NSRange(location: m.range.location, length: 1))
            mark(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        // ==highlight==
        if syntax.contains(.highlight) {
            each(#"==(?=\S)(.+?)(?<=\S)=="#) { m in
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: m.range(at: 1))
                mark(NSRange(location: m.range.location, length: 2))
                mark(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
            }
        }
        // `code`
        each(#"`([^`\n]+)`"#) { m in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: read ? 13.5 : 14, weight: .regular), range: m.range(at: 1))
            if read { storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: m.range(at: 1)) }
            mark(NSRange(location: m.range.location, length: 1))
            mark(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        // [^an inline footnote], iA Writer's kind: small and raised in Read.
        if syntax.contains(.inlineFootnotes) {
            each(#"\[\^([^\]]+)\]"#) { m in
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 1))
                if read {
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 11), .baselineOffset: 5], range: m.range(at: 1))
                }
                mark(NSRange(location: m.range.location, length: 2))
                mark(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
            }
        }
        // [links](url "title"), not images.
        each(#"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#) { m in
            storage.addAttribute(.foregroundColor, value: read ? look.links : NSColor.linkColor, range: m.range(at: 1))
            if read { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1)) }
            mark(NSRange(location: m.range.location, length: 1))
            mark(NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1))))
        }
        // ![images](url "caption"): kept visible, set back. In Read, a photo
        // on a line of its own that has loaded takes the line's place: the
        // line is hidden, and gets room above it where BodyNSTextView draws
        // the photo. TextKit leaves out the space before a document's first
        // paragraph, so a photo there makes its line tall instead.
        each(imagePattern) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
            guard read else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: m.range)
            let line = text.lineRange(for: m.range)
            guard let size = images[text.substring(with: m.range(at: 1))],
                  text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == text.substring(with: m.range),
                  size.width > 0, size.height > 0 else { return }
            let scale = min(1, (look.width ?? 600) / size.width, 520 / size.height)
            let shown = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let style = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            let room = shown.height
            mark(m.range)
            style.lineSpacing = 0
            style.minimumLineHeight = imageLine + (line.location == 0 ? room : 0)
            style.maximumLineHeight = style.minimumLineHeight
            style.paragraphSpacingBefore = line.location == 0 ? 0 : room
            storage.addAttributes([.paragraphStyle: style, .inlineImage: InlineImage(url: text.substring(with: m.range(at: 1)), size: shown)], range: line)
        }
        // ^^^callouts^^^, one line or fenced.
        if syntax.contains(.callouts) {
            each(#"\^\^\^([\s\S]*?)\^\^\^"#, []) { m in
                if read { storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.12), range: m.range(at: 1)) }
                mark(NSRange(location: m.range.location, length: 3))
                mark(NSRange(location: NSMaxRange(m.range) - 3, length: 3))
            }
        }
        // > quotes, list markers, rules and {{TOC}}: faded in both views.
        each(#"^(>[ \t]?)(.*)$"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
            if read { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2)) }
        }
        each(#"^[ \t]*([-*+]|\d+\.)[ \t]"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
        }
        each(#"^(\*\*\*|---|___)[ \t]*$"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
        }
        if syntax.contains(.toc) {
            each(#"\{\{TOC\}\}"#) { m in
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
            }
        }
        // Tables last, so cells are measured with their links and bold done.
        for table in tables(in: text) {
            styleTable(table, in: storage, mode: mode, look: look, mark: mark, trait: trait)
        }
        storage.endEditing()
    }

    /// A pipe table: its rows' cells (the text inside, trimmed) and the
    /// |---| line under the header.
    struct Table {
        var rows: [(line: NSRange, cells: [NSRange])]
        var divider: NSRange
    }

    static func tables(in text: NSString) -> [Table] {
        var lines: [NSRange] = []
        var at = 0
        while at < text.length {
            let line = text.lineRange(for: NSRange(location: at, length: 0))
            lines.append(line)
            at = NSMaxRange(line)
        }
        func content(_ line: NSRange) -> String {
            text.substring(with: line).trimmingCharacters(in: .newlines)
        }
        func isRow(_ line: NSRange) -> Bool {
            let s = content(line)
            return s.contains("|") && !s.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let divider = try! NSRegularExpression(pattern: #"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)
        func isDivider(_ line: NSRange) -> Bool {
            let s = content(line)
            return s.contains("|") && divider.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        }

        var tables: [Table] = []
        var i = 0
        while i + 1 < lines.count {
            guard isRow(lines[i]), !isDivider(lines[i]), isDivider(lines[i + 1]) else { i += 1; continue }
            var rows = [(lines[i], cells(in: lines[i], of: text))]
            var j = i + 2
            while j < lines.count, isRow(lines[j]) {
                rows.append((lines[j], cells(in: lines[j], of: text)))
                j += 1
            }
            tables.append(Table(rows: rows, divider: lines[i + 1]))
            i = j
        }
        return tables
    }

    /// The cells of one row, split on pipes that aren't escaped. An empty
    /// cell is an empty range where its text would go.
    static func cells(in line: NSRange, of text: NSString) -> [NSRange] {
        var end = NSMaxRange(line)
        while end > line.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        var pipes: [Int] = []
        for k in line.location..<end where text.character(at: k) == 124 && (k == line.location || text.character(at: k - 1) != 92) {
            pipes.append(k)
        }
        func blank(_ k: Int) -> Bool { [32, 9].contains(text.character(at: k)) }
        var bounds = [line.location - 1] + pipes + [end]
        // A leading or trailing pipe doesn't open a cell.
        if let first = pipes.first, (line.location..<first).allSatisfy(blank) { bounds.removeFirst() }
        if let last = pipes.last, last + 1 <= end, (last + 1..<end).allSatisfy(blank), bounds.count > 2 { bounds.removeLast() }
        var cells: [NSRange] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            var start = a + 1, stop = b
            while start < stop, blank(start) { start += 1 }
            while stop > start, blank(stop - 1) { stop -= 1 }
            cells.append(NSRange(location: start, length: stop - start))
        }
        return cells
    }

    /// How a column's cells sit, from the colons in the |---| line.
    enum Alignment { case left, center, right }

    static func alignments(_ table: Table, in text: NSString) -> [Alignment] {
        cells(in: table.divider, of: text).map { cell in
            let s = text.substring(with: cell)
            switch (s.hasPrefix(":"), s.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }
    }

    /// Markdown fades the pipes and the |---| line. Read hides them, bolds
    /// the header and lays the cells out in columns: the hidden pipe before
    /// each cell is kerned out to where the cell starts, and a wrapped last
    /// cell hangs under its own column. Each row is tagged with the grid's
    /// geometry for BodyNSTextView to draw. The text itself is never touched.
    private static func styleTable(_ table: Table, in storage: NSTextStorage, mode: BodyMode, look: ReadLook,
                                   mark: (NSRange) -> Void, trait: (NSRange, NSFontTraitMask) -> Void) {
        func gaps(_ row: (line: NSRange, cells: [NSRange])) -> [NSRange] {
            var gaps: [NSRange] = []
            var from = row.line.location
            for cell in row.cells + [NSRange(location: NSMaxRange(row.line), length: 0)] {
                gaps.append(NSRange(location: from, length: cell.location - from))
                from = NSMaxRange(cell)
            }
            return gaps
        }
        guard mode == .read else {
            for row in table.rows { gaps(row).forEach { storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: $0) } }
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: table.divider)
            return
        }

        table.rows[0].cells.forEach { trait($0, .boldFontMask) }
        for row in table.rows { gaps(row).forEach(mark) }
        mark(table.divider)
        let flat = NSMutableParagraphStyle()
        flat.maximumLineHeight = 1
        storage.addAttribute(.paragraphStyle, value: flat, range: table.divider)

        func width(_ range: NSRange) -> CGFloat {
            range.length == 0 ? 0 : storage.attributedSubstring(from: range).size().width
        }
        // Each column as wide as its widest cell. All but the last stop at a
        // point, so one long cell can't push the rest off the page; the last
        // wraps instead.
        let pad: CGFloat = 10
        let columns = table.rows.map(\.cells.count).max() ?? 0
        var widths = [CGFloat](repeating: 0, count: columns)
        for row in table.rows {
            for (c, cell) in row.cells.enumerated() {
                widths[c] = max(widths[c], c == columns - 1 ? width(cell) : min(width(cell), 260))
            }
        }
        var x: [CGFloat] = [pad]
        for w in widths.dropLast() { x.append(x.last! + w + 2 * pad) }
        let align = alignments(table, in: storage.string as NSString)

        let base = baseAttributes(.read, look)[.paragraphStyle] as! NSParagraphStyle
        let lines = x.dropFirst().map { $0 - pad }
        let right = x.last! + widths.last! + pad
        for (r, row) in table.rows.enumerated() {
            let style = base.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = x.last!
            style.tailIndent = -pad
            style.paragraphSpacingBefore = 0
            style.paragraphSpacing = 2
            // Where the line has got to, so the next hidden pipe knows how
            // far to kern.
            var reached: CGFloat = 0
            for (c, cell) in row.cells.enumerated() {
                let gapStart = c == 0 ? row.line.location : NSMaxRange(row.cells[c - 1])
                let gap = NSRange(location: gapStart, length: cell.location - gapStart)
                let slack = max(widths[c] - width(cell), 0)
                let shift = c < align.count ? [.left: 0, .center: slack / 2, .right: slack][align[c]]! : 0
                reached += width(gap)
                if gap.length > 0 {
                    let kern = max(x[c] + shift - reached, c == 0 ? 0 : pad)
                    storage.addAttribute(.kern, value: kern, range: NSRange(location: cell.location - 1, length: 1))
                    reached += kern
                } else {
                    style.firstLineHeadIndent = pad
                    reached = pad
                }
                reached += width(cell)
            }
            storage.addAttribute(.paragraphStyle, value: style, range: row.line)
            let grid = TableGrid(lines: lines, right: right, header: r == 0)
            storage.addAttribute(.tableGrid, value: grid, range: row.line)
        }
        // The divider belongs to the header's cell, so the grid has no gap.
        if let header = storage.attribute(.tableGrid, at: table.rows[0].line.location, effectiveRange: nil) {
            storage.addAttribute(.tableGrid, value: header, range: table.divider)
        }
    }

    /// The height of a photo's hidden `![](…)` line, under the photo.
    static let imageLine: CGFloat = 1

    private static let imagePattern = #"!\[[^\]\n]*\]\(([^)\s]+)[^)\n]*\)"#

    /// The addresses of the body's images, for loading.
    static func imageURLs(in text: String) -> [String] {
        guard text.contains("!["), let regex = try? NSRegularExpression(pattern: imagePattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map { (text as NSString).substring(with: $0.range(at: 1)) }
    }

    static func baseFont(_ mode: BodyMode, _ look: ReadLook = .standard) -> NSFont {
        mode == .read ? look.body : .monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    static func baseAttributes(_ mode: BodyMode, _ look: ReadLook = .standard) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        if mode == .read, let height = look.lineHeight {
            // The site's line height, as CSS sets it.
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
        } else {
            // Same line pitch in both views (18 + 4, 17 + 5), so switching
            // doesn't move the text. The blank lines in the markdown already
            // space the paragraphs.
            paragraph.lineSpacing = mode == .read ? 4 : 5
        }
        let color = mode == .read ? look.text : NSColor.labelColor
        return [.font: baseFont(mode, look), .foregroundColor: color, .paragraphStyle: paragraph]
    }
}

/// A table row's grid, in text container points: the column lines between
/// cells and the right edge. The left edge is 0.
final class TableGrid: NSObject {
    let lines: [CGFloat]
    let right: CGFloat
    let header: Bool

    init(lines: [CGFloat], right: CGFloat, header: Bool) {
        self.lines = lines
        self.right = right
        self.header = header
    }
}

extension NSAttributedString.Key {
    static let tableGrid = NSAttributedString.Key("canteiroTableGrid")
}
