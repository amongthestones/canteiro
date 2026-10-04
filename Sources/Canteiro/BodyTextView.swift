import AppKit
import SwiftUI

/// The body editor: a TextKit 2 text view that grows to fit its text, so the
/// fields and the body scroll together as one page. SwiftUI's TextEditor
/// stays at its first height when scrolling is off and clips the rest.
///
/// SwiftUI alone sizes the view. The text view never resizes itself, and its
/// height is measured on a copy of the text, never by laying out the live
/// view: either one makes AppKit and SwiftUI resize each other in a loop until
/// AppKit stops the app (a crash on opening the preview panel).
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 320

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: true)
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

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        view.string = text
        view.textStorage?.setAttributes(view.typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        guard view.string != text else { return }
        view.string = text
        view.textStorage?.setAttributes(view.typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let height = context.coordinator.height(of: text, width: width, attributes: view.typingAttributes)
        return CGSize(width: width, height: max(height, minHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        /// The last measurement. SwiftUI asks for the same size many times.
        private var measured: (text: String, width: CGFloat, height: CGFloat)?

        init(_ parent: BodyTextView) { self.parent = parent }

        func height(of text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
            if let measured, measured.width == width, measured.text == text { return measured.height }
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
            let box = NSAttributedString(string: text, attributes: attributes)
                .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
            // One spare line, so a trailing newline has room and the caret
            // never sits on the bottom edge.
            let height = ceil(box.height + font.boundingRectForFont.height + 8)
            measured = (text, width, height)
            return height
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
