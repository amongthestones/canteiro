import SwiftUI

/// Saves an editor's changes a moment after typing stops, on ⌘S, and when
/// the editor closes, the way iA Writer does. Shows a bar when the file
/// changed on disk or couldn't be written.
struct Autosave: ViewModifier {
    @Environment(SiteStore.self) private var store
    let item: SchemaItem
    let id: Entry.ID
    let data: FieldValue
    let text: String?
    @State private var pending: Task<Void, Never>?
    /// The revision this editor opened at. After "Use the File on Disk" the
    /// store moves on, and this editor's edits must not be saved on close.
    @State private var revision: Int?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { banner }
            .onAppear { revision = store.revisions[id] ?? 0 }
            .onChange(of: data) { schedule() }
            .onChange(of: text) { schedule() }
            .onDisappear { saveNow() }
            .focusedSceneValue(\.saveEntry, saveNow)
    }

    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        pending?.cancel()
        pending = nil
        guard revision == (store.revisions[id] ?? 0) else { return }
        store.save(item, id: id, data: data, body: text)
    }

    @ViewBuilder
    private var banner: some View {
        if store.conflicts.contains(id) {
            Bar(systemImage: "exclamationmark.triangle.fill", tint: .orange,
                text: "This file changed on disk since Canteiro read it. Your edits aren't saved.") {
                Button("Use the File on Disk") { store.reread(item, id: id) }
                Button("Keep My Version") { store.save(item, id: id, data: data, body: text, overwrite: true) }
            }
        } else if let error = store.saveErrors[id] {
            Bar(systemImage: "xmark.octagon.fill", tint: .red, text: "Couldn't save: \(error)") {
                Button("Try Again") { saveNow() }
            }
        }
    }
}

/// A strip across the top of an editor: a problem and what to do about it.
struct Bar<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer(minLength: 8)
            actions.controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension View {
    func autosave(_ item: SchemaItem, id: Entry.ID, data: FieldValue, body: String?) -> some View {
        modifier(Autosave(item: item, id: id, data: data, text: body))
    }
}

extension FocusedValues {
    /// The open editor's save, for File › Save.
    @Entry var saveEntry: (() -> Void)?
}

struct SaveCommand: Commands {
    @FocusedValue(\.saveEntry) private var saveEntry

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") { saveEntry?() }
                .keyboardShortcut("s")
                .disabled(saveEntry == nil)
        }
    }
}
