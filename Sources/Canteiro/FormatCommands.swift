import AppKit
import SwiftUI

/// The Format menu, with iA Writer's shortcuts. Each item goes to whatever
/// has focus, so it acts in the body editor and nowhere else.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            item("Bold", #selector(BodyNSTextView.formatBold(_:)), "b")
            item("Italic", #selector(BodyNSTextView.formatItalic(_:)), "i")
            item("Strikethrough", #selector(BodyNSTextView.formatStrikethrough(_:)), "u", [.command, .option])
            item("Highlight", #selector(BodyNSTextView.formatHighlight(_:)), "u", [.command, .shift])
            item("Code", #selector(BodyNSTextView.formatCode(_:)), "j")
            Divider()
            item("Link", #selector(BodyNSTextView.formatLink(_:)), "k")
            item("Image", #selector(BodyNSTextView.formatImage(_:)), "k", [.command, .option])
            item("Footnote", #selector(BodyNSTextView.formatFootnote(_:)), "k", [.command, .control])
            Divider()
            Menu("Heading") {
                item("Heading 1", #selector(BodyNSTextView.formatHeading1(_:)), "1")
                item("Heading 2", #selector(BodyNSTextView.formatHeading2(_:)), "2")
                item("Heading 3", #selector(BodyNSTextView.formatHeading3(_:)), "3")
                item("Heading 4", #selector(BodyNSTextView.formatHeading4(_:)), "4")
                item("Heading 5", #selector(BodyNSTextView.formatHeading5(_:)), "5")
                item("Heading 6", #selector(BodyNSTextView.formatHeading6(_:)), "6")
            }
            item("Ordered List", #selector(BodyNSTextView.formatOrderedList(_:)), "l", [.command, .shift])
            item("Task List", #selector(BodyNSTextView.formatTaskList(_:)), "l", [.command, .option])
            item("Ordered Task List", #selector(BodyNSTextView.formatOrderedTaskList(_:)), "l", [.command, .option, .shift])
            item("Mark Task as Done", #selector(BodyNSTextView.formatToggleTask(_:)), "x", [.command, .option])
            item("Code Block", #selector(BodyNSTextView.formatCodeBlock(_:)), "j", [.command, .shift])
            Divider()
            item("Move Line Up", #selector(BodyNSTextView.formatMoveLineUp(_:)), .upArrow, [.command, .option])
            item("Move Line Down", #selector(BodyNSTextView.formatMoveLineDown(_:)), .downArrow, [.command, .option])
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: KeyEquivalent,
                      _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: modifiers)
    }
}
