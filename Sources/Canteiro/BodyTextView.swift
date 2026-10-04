import AppKit
import SwiftUI

/// The body editor: a TextKit 2 text view that grows to fit its text, so the
/// fields and the body scroll together as one page. SwiftUI's TextEditor
/// stays at its first height when scrolling is off and clips the rest.
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
        view.isVerticallyResizable = true
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
        guard let width = proposal.width, width.isFinite, width > 0,
              let layout = view.textLayoutManager, let container = view.textContainer else { return nil }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: layout.documentRange)
        let height = layout.usageBoundsForTextContainer.height
        return CGSize(width: width, height: max(ceil(height) + 8, minHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView

        init(_ parent: BodyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
