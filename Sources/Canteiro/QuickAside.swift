import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A small window for one thought: type it, pick its language, ⌘↩ to save.
/// Opens from File › New Aside (⇧⌘A) or ⌃⌥A from any app.
struct QuickAsideView: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var text = ""
    @State private var language = ""

    private var item: SchemaItem? { store.streamItem }
    private var limit: Int { item?.textField?.maxLength ?? 280 }
    private var languageField: FieldSpec? {
        item?.dataFields.first { $0.type == "select" && $0.key.hasPrefix("lang") }
    }
    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= limit && item != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsideTextView(text: $text)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("One thought, \(limit) characters at most.")
                            .font(.system(size: AsideTextView.fontSize))
                            .foregroundStyle(.tertiary)
                            // Room for the caret, so it doesn't cut the first letter.
                            .padding(.leading, 3)
                            .allowsHitTesting(false)
                    }
                }
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .frame(height: 120)
            HStack(spacing: 10) {
                if let field = languageField, let options = field.options {
                    Picker("Language", selection: $language) {
                        ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text("\(text.count) / \(limit)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(text.count > limit ? .red : .secondary)
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            if item == nil {
                Text("This site has no stream of short posts to add to.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { text = "" }
        // The site may still be loading when the window opens.
        .onChange(of: languageField?.key, initial: true) {
            guard let field = languageField, field.options?.contains(where: { $0.value == language }) != true else { return }
            language = field.defaultString ?? field.options?.first?.value ?? ""
        }
    }

    private func save() {
        do {
            try store.createAside(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language.isEmpty ? nil : language)
            close()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func close() {
        text = ""
        dismissWindow(id: "aside")
    }
}

/// The aside's text box. SwiftUI's TextEditor starts its caret in the
/// default font and inset, so it sat off from the hint and jumped on the
/// first letter. Here the empty view already types in the right font, with
/// no inset, so the caret lines up with the hint.
struct AsideTextView: NSViewRepresentable {
    static let fontSize: CGFloat = 15
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        let font = NSFont.systemFont(ofSize: Self.fontSize)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.font = font
        view.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        view.string = text
        view.delegate = context.coordinator
        // The window isn't on screen yet; take the keyboard once it is.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AsideTextView
        init(_ parent: AsideTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

/// ⌃⌥A from any app, through Carbon's hotkey API: it needs no accessibility
/// permission.
final class AsideHotKey {
    static let pressed = Notification.Name("CanteiroAsideHotKey")
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            NotificationCenter.default.post(name: AsideHotKey.pressed, object: nil)
            return noErr
        }, 1, &type, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4353_5452), id: 1) // "CSTR"
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}

/// The bar along the bottom while files go up to R2, and the last error.
struct UploadBar: View {
    @Environment(SiteStore.self) private var store

    var body: some View {
        if !store.uploads.isEmpty || store.lastError != nil || store.build.state != .idle {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.uploads) { upload in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.circle").foregroundStyle(.tint)
                            Text("Uploading \(upload.name)").lineLimit(1)
                            ProgressView(value: upload.progress).frame(width: 160)
                            Text("\(Int(upload.progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    BuildRow(build: store.build)
                    if let error = store.lastError {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text(error).lineLimit(2)
                            Spacer()
                            Button("Dismiss") { store.lastError = nil }.controlSize(.small)
                        }
                    }
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}

/// The build after a push: building, then live or failed, with a link to
/// the host's page for it. Live goes away on its own after a while.
private struct BuildRow: View {
    let build: BuildWatch
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch build.state {
        case .idle:
            EmptyView()
        case .building(let name, let url):
            row {
                ProgressView().controlSize(.small)
                Text(name.map { "\($0) is building the site…" } ?? "Waiting for the build to start…")
            } url: { url }
        case .live(let name, let url):
            row {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Live. \(name) finished building the site.")
            } url: { url }
            .task {
                try? await Task.sleep(for: .seconds(30))
                build.dismiss()
            }
        case .failed(let name, let detail, let url):
            row {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("\(name) couldn't build the site\(detail.map { ": \($0)" } ?? ".")").lineLimit(2)
            } url: { url }
        }
    }

    private func row(@ViewBuilder _ content: () -> some View, url: () -> URL?) -> some View {
        let link = url()
        return HStack(spacing: 10) {
            content()
            Spacer()
            if let link {
                Button("Show Log") { openURL(link) }.controlSize(.small)
            }
            Button("Dismiss") { build.dismiss() }.controlSize(.small)
        }
    }
}
