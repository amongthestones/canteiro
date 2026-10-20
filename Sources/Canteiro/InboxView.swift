import SwiftUI

/// The drafts waiting in the inbox folder: the list on the left, the selected one on the right, as a
/// collection is shown. Edits save to the draft's file; Import makes it an
/// entry.
struct InboxView: View {
    @Environment(SiteStore.self) private var store
    @AppStorage("bodyMode") private var bodyMode = BodyMode.markdown
    @Environment(DraftInbox.self) private var inbox
    @AppStorage("listWidth") private var listWidth = 320.0
    @State private var error: String?

    private var selectedDraft: InboxDraft? {
        inbox.selected.flatMap { url in inbox.drafts.first { $0.url == url } }
    }

    var body: some View {
        @Bindable var inbox = inbox
        Group {
            if let problem = inbox.problem {
                ContentUnavailableView {
                    Label("Can't Read the Folder", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(problem).textSelection(.enabled)
                } actions: {
                    Button("Choose Folder…") { inbox.chooseFolder() }
                }
            } else {
                HStack(spacing: 0) {
                    List(inbox.drafts, selection: $inbox.selected) { draft in
                        DraftRow(draft: draft).tag(draft.url)
                    }
                    .frame(width: listWidth)
                    .overlay {
                        if inbox.drafts.isEmpty {
                            ContentUnavailableView {
                                Label("No Drafts Waiting", systemImage: "tray")
                            } description: {
                                Text("Drafts you save in \(inbox.folder?.lastPathComponent ?? "the inbox folder") show up here, from the phone or the Mac.")
                            }
                        }
                    }

                    ResizeHandle(width: $listWidth, range: 240...440)

                    Group {
                        if let draft = selectedDraft {
                            DraftEditor(draft: draft).id(draft.url)
                        } else {
                            ContentUnavailableView("No Draft Selected", systemImage: "doc.text")
                        }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSubtitle("Inbox · \(inbox.drafts.count)")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Import", systemImage: "square.and.arrow.down") {
                    if let draft = selectedDraft { importDraft(draft) }
                }
                .help("Make it a draft \(importLabel), and move the file to Imported in \(inbox.app)")
                .disabled(selectedDraft == nil)
            }
            ToolbarItem(placement: .navigation) {
                Menu("Folder", systemImage: "folder") {
                    Button("Show in Finder") { inbox.folder.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) } }
                    Button("Choose Folder…") { inbox.chooseFolder() }
                }
            }
        }
        .alert("Couldn't Import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .onAppear { inbox.refresh() }
    }

    /// "in Posts", from the collection's label.
    private var importLabel: String {
        inbox.collection.flatMap { store.schema?.item($0) }.map { "in \($0.label)" } ?? "entry"
    }

    private func importDraft(_ draft: InboxDraft) {
        guard let key = inbox.collection, let item = store.schema?.item(key) else { return }
        do {
            try inbox.importDraft(draft, into: item, store: store)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A draft in the list, laid out like a post's row.
struct DraftRow: View {
    let draft: InboxDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(draft.modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(draft.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(.vertical, 3)
        .padding(.leading, 13)
    }
}

/// The draft's file as it is, frontmatter and heading included, in the
/// body editor. Saves a moment after typing stops, on ⌘S and on close.
/// When the file changes elsewhere (the phone), it reloads, or asks first
/// if there are edits here.
struct DraftEditor: View {
    @Environment(SiteStore.self) private var store
    @Environment(DraftInbox.self) private var inbox
    @AppStorage("bodyMode") private var bodyMode = BodyMode.markdown
    let draft: InboxDraft
    @State private var text = ""
    @State private var loaded = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ScrollView {
            BodyTextView(text: $text, mode: bodyMode, syntax: store.config.extras, look: store.readLook,
                         uploadPhoto: EntryEditor.photoUploader(store), onError: { store.lastError = $0 })
                .frame(maxWidth: bodyMode == .read ? store.readLook.width : nil, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bodyMode == .read ? store.readLook.background.map(Color.init(nsColor:)) : nil)
        .safeAreaInset(edge: .top, spacing: 0) { banner }
        .onAppear {
            text = inbox.open(draft.url)
            loaded = true
        }
        .onChange(of: text) {
            guard loaded else { return }
            inbox.edit(draft.url, text)
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                inbox.save(draft.url)
            }
        }
        .onChange(of: draft.modified) { reloadIfChanged() }
        .onDisappear {
            pending?.cancel()
            inbox.save(draft.url)
        }
        .focusedSceneValue(\.saveEntry) { inbox.save(draft.url) }
    }

    private func reloadIfChanged() {
        guard inbox.changedOnDisk(draft.url), !inbox.hasUnsaved(draft.url) else { return }
        text = inbox.open(draft.url)
    }

    @ViewBuilder
    private var banner: some View {
        if inbox.conflicts.contains(draft.url) {
            Bar(systemImage: "exclamationmark.triangle.fill", tint: .orange,
                     text: "This draft changed in \(inbox.app) since Canteiro read it. Your edits aren't saved.") {
                Button("Use the File on Disk") {
                    inbox.revert(draft.url)
                    text = inbox.open(draft.url)
                }
                Button("Keep My Version") { inbox.save(draft.url, overwrite: true) }
            }
        } else if let error = inbox.saveErrors[draft.url] {
            Bar(systemImage: "xmark.octagon.fill", tint: .red, text: "Couldn't save: \(error)") {
                Button("Try Again") { inbox.save(draft.url) }
            }
        }
    }
}
