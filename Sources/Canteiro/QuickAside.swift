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
    @FocusState private var focused: Bool

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
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .frame(height: 120)
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("One thought, \(limit) characters at most.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
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
        .onAppear {
            text = ""
            language = languageField?.defaultString ?? languageField?.options?.first?.value ?? ""
            focused = true
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
        if !store.uploads.isEmpty || store.lastError != nil {
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
