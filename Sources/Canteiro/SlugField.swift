import SwiftUI

/// Renaming the open entry, handed down to its slug field by EntryEditor.
struct EntryRename {
    let slug: String
    let check: (String) -> SiteStore.RenameCheck?
    let perform: (String) throws -> Void
}

extension EnvironmentValues {
    @Entry var entryRename: EntryRename?
}

/// A collection entry's slug, which is its file's name. Typing changes
/// nothing until Return or leaving the field; then the entry is renamed,
/// after asking first if it's live, since links to it would break.
struct SlugField: View {
    let spec: FieldSpec
    let rename: EntryRename
    @State private var text = ""
    @State private var asking: SiteStore.RenameCheck?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(spec.slug?.label ?? "Slug", text: $text)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .labelsHidden()
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let description = spec.slug?.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { text = rename.slug }
        .confirmationDialog("Change the address of a live entry?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            presenting: asking) { _ in
            Button("Change Address") { perform() }
            Button("Cancel", role: .cancel) { text = rename.slug }
        } message: { check in
            Text(message(check))
        }
    }

    private func commit() {
        guard asking == nil else { return }
        let slug = Renamer.slug(text, replacing: rename.slug)
        guard slug != rename.slug, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            text = rename.slug
            error = nil
            return
        }
        text = slug
        if let check = rename.check(slug), check.isLive {
            asking = check
        } else {
            perform()
        }
    }

    private func perform() {
        do {
            try rename.perform(text)
            error = nil
        } catch {
            self.error = error.localizedDescription
            text = rename.slug
        }
    }

    private func message(_ check: SiteStore.RenameCheck) -> String {
        guard let old = check.oldAddress, let new = check.newAddress else {
            return "It's published, so links to its old address will stop working."
        }
        if let file = check.redirects {
            return "Links to \(old) would break, so Canteiro adds a redirect from there to \(new) in \(file)."
        }
        return "Links to \(old) will stop working. Add a redirect to \(new) so they keep working."
    }
}
