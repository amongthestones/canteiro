import AppKit

/// How the body is shown. Both edit the same text; Rich only draws it
/// differently, so the file on disk is exactly what was typed either way.
enum BodyMode: String {
    case markdown, rich
}

/// Styles the body's markdown in place. Markdown: a mono font with the marks
/// faded, as iA Writer does. Rich: a reading font with the marks hidden and
/// the result shown. Covers the site's own syntax too: ==highlights==,
/// [^inline footnotes], ^^^callouts^^^ and {{TOC}}.
enum MarkdownStyler {
    static func style(_ storage: NSTextStorage, mode: BodyMode) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let rich = mode == .rich
        let base = baseFont(mode)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(mode), range: all)

        func each(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines], _ body: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: storage.string, range: all) { match, _, _ in if let match { body(match) } }
        }
        func mark(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            if rich {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: range)
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
            let sizes: [CGFloat] = [26, 21, 18, 16, 15, 15]
            let font = rich ? NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold)
                            : NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
            storage.addAttribute(.font, value: font, range: m.range(at: 3))
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
        each(#"==(?=\S)(.+?)(?<=\S)=="#) { m in
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: m.range(at: 1))
            mark(NSRange(location: m.range.location, length: 2))
            mark(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        // `code`
        each(#"`([^`\n]+)`"#) { m in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: rich ? 13.5 : 14, weight: .regular), range: m.range(at: 1))
            if rich { storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: m.range(at: 1)) }
            mark(NSRange(location: m.range.location, length: 1))
            mark(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        // [^an inline footnote], iA Writer's kind: small and raised in Rich.
        each(#"\[\^([^\]]+)\]"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 1))
            if rich {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 11), .baselineOffset: 5], range: m.range(at: 1))
            }
            mark(NSRange(location: m.range.location, length: 2))
            mark(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        // [links](url "title"), not images.
        each(#"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range(at: 1))
            if rich { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1)) }
            mark(NSRange(location: m.range.location, length: 1))
            mark(NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1))))
        }
        // ![images](url "caption"): kept visible, set back.
        each(#"!\[[^\]\n]*\]\([^)\n]+\)"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
            if rich { storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: m.range) }
        }
        // ^^^callouts^^^, one line or fenced.
        each(#"\^\^\^([\s\S]*?)\^\^\^"#, []) { m in
            if rich { storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.12), range: m.range(at: 1)) }
            mark(NSRange(location: m.range.location, length: 3))
            mark(NSRange(location: NSMaxRange(m.range) - 3, length: 3))
        }
        // > quotes, list markers, rules, {{TOC}}: faded in both views.
        each(#"^(>[ \t]?)(.*)$"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
            if rich { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2)) }
        }
        each(#"^[ \t]*([-*+]|\d+\.)[ \t]"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
        }
        each(#"^(\*\*\*|---|___)[ \t]*$"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
        }
        each(#"\{\{TOC\}\}"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
        }
        storage.endEditing()
    }

    static func baseFont(_ mode: BodyMode) -> NSFont {
        mode == .rich ? .systemFont(ofSize: 15) : .monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    static func baseAttributes(_ mode: BodyMode) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = mode == .rich ? 6 : 5
        paragraph.paragraphSpacing = mode == .rich ? 6 : 0
        return [.font: baseFont(mode), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }
}
