import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The body editor: a TextKit 2 text view that grows to fit its text, so the
/// fields and the body scroll together as one page. SwiftUI's TextEditor
/// stays at its first height when scrolling is off and clips the rest.
///
/// SwiftUI alone sizes the view. The text view never resizes itself, and its
/// height is measured on a copy of the text, never by laying out the live
/// view: either one can make AppKit and SwiftUI resize each other in a loop.
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    var mode: BodyMode = .markdown
    var minHeight: CGFloat = 320
    /// Turns a dropped photo into the markdown to insert (`![](https://…)`).
    var uploadPhoto: (@MainActor (URL) async throws -> String)?
    var onError: (@MainActor (String) -> Void)?

    func makeNSView(context: Context) -> BodyNSTextView {
        let view = BodyNSTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        // Markdown is typed as typed: no curly quotes or dashes swapped in.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.string = text
        view.delegate = context.coordinator
        view.onImageFiles = { [weak coordinator = context.coordinator] files, index in
            coordinator?.insertPhotos(files, at: index) ?? false
        }
        context.coordinator.view = view
        context.coordinator.restyle()
        return view
    }

    func updateNSView(_ view: BodyNSTextView, context: Context) {
        let coordinator = context.coordinator
        let modeChanged = coordinator.parent.mode != mode
        coordinator.parent = self
        if view.string != text {
            view.string = text
            coordinator.restyle()
        } else if modeChanged {
            coordinator.restyle()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BodyNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0, let storage = view.textStorage else { return nil }
        let height = context.coordinator.height(of: storage, width: width)
        return CGSize(width: width, height: max(height, minHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        weak var view: BodyNSTextView?
        /// The last measurement. SwiftUI asks for the same size many times.
        private var measured: (text: String, mode: BodyMode, width: CGFloat, height: CGFloat)?

        init(_ parent: BodyTextView) { self.parent = parent }

        func restyle() {
            guard let view, let storage = view.textStorage else { return }
            MarkdownStyler.style(storage, mode: parent.mode)
            view.typingAttributes = MarkdownStyler.baseAttributes(parent.mode)
            measured = nil
            // A grid moves with its table, and TextKit only redraws the text.
            if parent.mode == .rich, storage.string.contains("|") { view.needsDisplay = true }
        }

        func height(of storage: NSTextStorage, width: CGFloat) -> CGFloat {
            if let measured, measured.width == width, measured.mode == parent.mode, measured.text == storage.string {
                return measured.height
            }
            let copy = NSAttributedString(attributedString: storage)
            let box = copy.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
            // One spare line, so a trailing newline has room and the caret
            // never sits on the bottom edge.
            let line = MarkdownStyler.baseFont(parent.mode).boundingRectForFont.height
            let height = ceil(box.height + line + 8)
            measured = (storage.string, parent.mode, width, height)
            return height
        }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
            restyle()
        }

        /// Puts a placeholder where each photo was dropped, then swaps in its
        /// markdown once it's processed and uploaded.
        func insertPhotos(_ files: [URL], at index: Int) -> Bool {
            guard let view, let upload = parent.uploadPhoto else { return false }
            var at = index
            for file in files {
                let token = "![Uploading \(file.lastPathComponent)…](canteiro-upload-\(UUID().uuidString.prefix(8)))"
                let text = view.string as NSString
                // A photo sits in its own paragraph, so it can take a caption.
                let before = at > 0 && text.character(at: at - 1) != 10 ? "\n\n" : ""
                let after = at < text.length && text.character(at: at) != 10 ? "\n\n" : ""
                let inserted = before + token + after
                replace(NSRange(location: at, length: 0), with: inserted)
                at += (inserted as NSString).length
                Task { @MainActor in
                    do {
                        let markdown = try await upload(file)
                        self.swap(token, for: markdown)
                    } catch {
                        self.swap(token, for: "")
                        self.parent.onError?("\(file.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            return true
        }

        private func swap(_ token: String, for replacement: String) {
            guard let view else { return }
            let range = (view.string as NSString).range(of: token)
            guard range.location != NSNotFound else { return }
            replace(range, with: replacement)
        }

        /// An undoable edit that SwiftUI hears about.
        private func replace(_ range: NSRange, with string: String) {
            guard let view, view.shouldChangeText(in: range, replacementString: string) else { return }
            view.textStorage?.replaceCharacters(in: range, with: string)
            view.didChangeText()
        }
    }
}

/// An NSTextView that hands dropped photos to the app instead of inserting
/// their file paths, and draws the grid of Rich tables.
final class BodyNSTextView: NSTextView {
    var onImageFiles: (([URL], Int) -> Bool)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTableGrids(in: dirtyRect)
    }

    /// Hairlines around and between the cells of each row MarkdownStyler
    /// tagged, a darker one under the header.
    private func drawTableGrids(in dirtyRect: NSRect) {
        guard let storage = textStorage, let layout = textLayoutManager,
              let content = layout.textContentManager, let container = textContainer else { return }
        let hairline = 1 / (window?.backingScaleFactor ?? 2)
        let origin = textContainerOrigin
        storage.enumerateAttribute(.tableGrid, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let grid = value as? TableGrid,
                  let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length) else { return }
            // The row's frame, with the divider folded into the header's.
            var frame = NSRect.null
            layout.enumerateTextLayoutFragments(from: start) { fragment in
                guard fragment.rangeInElement.location.compare(end) == .orderedAscending else { return false }
                frame = frame.union(fragment.layoutFragmentFrame)
                return true
            }
            guard !frame.isNull else { return }
            frame = frame.offsetBy(dx: origin.x, dy: origin.y)
            guard frame.intersects(dirtyRect.insetBy(dx: -2, dy: -2)) else { return }
            let left = origin.x, right = origin.x + min(grid.right, container.size.width)

            NSColor.separatorColor.setFill()
            for x in [0] + grid.lines + [right - left] {
                NSRect(x: left + x - hairline / 2, y: frame.minY, width: hairline, height: frame.height).fill()
            }
            if grid.header {
                NSRect(x: left, y: frame.minY, width: right - left, height: hairline).fill()
                NSColor.tertiaryLabelColor.setFill()
            }
            NSRect(x: left, y: frame.maxY - hairline, width: right - left, height: hairline).fill()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let photos = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        if !photos.isEmpty, let onImageFiles {
            let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            if onImageFiles(photos, index) { return true }
        }
        return super.performDragOperation(sender)
    }
}
