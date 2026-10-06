import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File › New Entry (⌘N) and the list's compose button. What it opens
/// depends on the collection: the quick aside window for asides, a file
/// picker for an episode's MP3, else a sheet that asks for the title.
struct NewEntryButton: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    var inMenu = false

    private var item: SchemaItem? {
        guard let key = store.selectedItem, let item = store.schema?.item(key), item.kind == .collection else { return nil }
        return item
    }

    var body: some View {
        if inMenu {
            button.keyboardShortcut("n")
        } else {
            button.help(item.map { "New entry in \($0.label) (⌘N)" } ?? "New entry")
        }
    }

    private var button: some View {
        Button("New Entry", systemImage: "square.and.pencil") {
            guard let item else { return }
            if item.isStream {
                openWindow(id: "aside")
            } else if store.isEpisodes(item) {
                pickAudio(for: item)
            } else {
                store.newEntryItem = item
            }
        }
        .disabled(item == nil || store.phase != .ready)
    }

    private func pickAudio(for item: SchemaItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3]
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Choose the episode's MP3. It goes up to R2, and the length, number and guid fill in."
        guard panel.runModal() == .OK else { return }
        for file in panel.urls { Task { await store.createEpisode(item, from: file) } }
    }
}

/// Asks for a new entry's title, which also names its file.
struct NewEntrySheet: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: SchemaItem
    @State private var title = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var titleSpec: FieldSpec? {
        item.slugField.flatMap { key in item.dataFields.first { $0.key == key } }
    }

    private var slug: String { Slug.make(title) }

    /// Where it will live: the page address when the collection has one,
    /// else the file name.
    private var address: String {
        if let template = item.previewUrl { return template.replacingOccurrences(of: "{slug}", with: slug) }
        return "\(slug).\(item.fileExtension)"
    }

    private var isBlank: Bool { title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Entry in \(item.label)").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                TextField(titleSpec?.title ?? "Title", text: $title, prompt: Text(titleSpec?.title ?? "Title"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(create)
                Text(isBlank ? " " : address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if item.dataFields.contains(where: { $0.key == "draft" }) {
                Text("It starts as a draft. Untick Draft when it's ready to go live.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBlank)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func create() {
        guard !isBlank else { return }
        do {
            try store.createEntry(item, title: title)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
