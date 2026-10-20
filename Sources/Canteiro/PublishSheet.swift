import SwiftUI

/// Commit and push: the changed files, each with its diff, and a message.
struct PublishSheet: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case ready
        case working(String)
        case pushed
        /// The commit is made; only the push failed. `behind`: GitHub has
        /// newer commits, so pulling first will fix it.
        case pushFailed(String, behind: Bool)
        case failed(String)
    }

    @State private var picked: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var diffs: [String: AttributedString] = [:]
    @State private var discarding: GitChange?
    @State private var message = ""
    @State private var phase: Phase = .ready
    @State private var branch = "main"

    private var changes: [GitChange] { store.changes }

    var body: some View {
        VStack(spacing: 0) {
            if phase == .pushed {
                done
            } else {
                Form {
                    Section {
                        ForEach(changes) { row($0) }
                    } header: {
                        Text("Changes")
                    } footer: {
                        Text("Commits the ticked files to \(branch) and pushes to GitHub. Cloudflare Pages builds the site from the push.")
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        TextField("Message", text: $message, prompt: Text("What changed"))
                    }
                }
                .formStyle(.grouped)
                .disabled(isWorking)
                Divider()
                footer
            }
        }
        .frame(width: 680)
        .frame(minHeight: phase == .pushed ? 0 : 520, idealHeight: phase == .pushed ? nil : 820)
        .task {
            if let site = store.siteURL { branch = await Task.detached { Git.branch(site) ?? "main" }.value }
            picked = Set(store.contentChanges.map(\.id))
            if let first = changes.first(where: { picked.contains($0.id) }) ?? changes.first { expanded = [first.id] }
            message = suggestedMessage()
        }
        .task(id: expanded) { await loadDiffs() }
        .onChange(of: changes) {
            // A discarded file leaves the list.
            picked.formIntersection(changes.map(\.id))
            diffs = [:]
            Task { await loadDiffs() }
        }
        .confirmationDialog(discardTitle, isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
                            presenting: discarding) { change in
            Button("Discard", role: .destructive) { Task { await store.discard(change) } }
        } message: { change in
            Text(change.isNew && change.code == "??"
                 ? "It isn't published yet, so the whole file goes to the Trash."
                 : "It goes back to the published version. Your version goes to the Trash.")
        }
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private func name(_ change: GitChange) -> String {
        store.title(forPath: change.path) ?? URL(fileURLWithPath: change.path).lastPathComponent
    }

    private var discardTitle: String {
        discarding.map { "Discard the changes to \(name($0))?" } ?? ""
    }

    /// A file: ticked to publish, opened to see what changed. The whole
    /// row opens it, with the chevron on the trailing edge.
    @ViewBuilder
    private func row(_ change: GitChange) -> some View {
        let open = expanded.contains(change.id)
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { picked.contains(change.id) },
                set: { if $0 { picked.insert(change.id) } else { picked.remove(change.id) } }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(name(change)).lineLimit(1)
                Text(change.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(change.isNew ? "New" : change.isDeleted ? "Deleted" : "Edited")
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                if open { expanded.remove(change.id) } else { expanded.insert(change.id) }
            }
        }
        .accessibilityAction(named: open ? "Hide Changes" : "Show Changes") {
            if open { expanded.remove(change.id) } else { expanded.insert(change.id) }
        }
        if open {
            VStack(alignment: .leading, spacing: 10) {
                let diff = Text(diffs[change.id] ?? AttributedString("…"))
                    .font(Self.isProse(change.path) ? .body : .system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                // As tall as the diff, scrolling past 420 points.
                ViewThatFits(in: .vertical) {
                    diff.fixedSize(horizontal: false, vertical: true)
                    ScrollView { diff }
                }
                .frame(maxHeight: 420)
                Button("Discard Changes…", role: .destructive) { discarding = change }
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    private func loadDiffs() async {
        guard let site = store.siteURL else { return }
        for change in changes where expanded.contains(change.id) && diffs[change.id] == nil {
            let text = await Task.detached { Git.diff(site, change) }.value
            diffs[change.id] = DiffStyle.words(text)
        }
    }

    static func isProse(_ path: String) -> Bool {
        ["md", "mdx", "mdoc", "markdown", "txt"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            switch phase {
            case .working(let step):
                ProgressView().controlSize(.small)
                Text(step).foregroundStyle(.secondary)
            case .failed(let error):
                Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
            case .pushFailed(let error, let behind):
                Label(behind ? "Committed, but GitHub has newer commits. Pull them first, then push." : "Committed, but the push failed: \(error)",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            default:
                Text("\(picked.count) of \(changes.count) files").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            if case .pushFailed(_, let behind) = phase {
                Button(behind ? "Pull and Push" : "Push Again") { push(pullFirst: behind) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Commit and Push") { publish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        }
        .padding(16)
    }

    private var done: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pushed to \(branch)").font(.headline)
                Text(BuildWatch.ghPath() == nil
                     ? "Your host builds the site from the push."
                     : "Your host builds the site from the push. How it's going shows at the bottom of the window.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func publish() {
        guard let site = store.siteURL else { return }
        let paths = changes.filter { picked.contains($0.id) }.map(\.path)
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .working("Committing…")
        Task {
            do {
                try await Task.detached { try Git.commit(site, paths: paths, message: text) }.value
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            store.refreshChanges()
            push(pullFirst: false)
        }
    }

    private func push(pullFirst: Bool) {
        guard let site = store.siteURL else { return }
        phase = .working(pullFirst ? "Pulling, then pushing…" : "Pushing…")
        Task {
            do {
                try await Task.detached {
                    if pullFirst { try Git.pullRebase(site) }
                    try Git.push(site)
                }.value
                phase = .pushed
                store.build.watch(site: site)
            } catch {
                let text = error.localizedDescription
                let behind = text.contains("fetch first") || text.contains("non-fast-forward") || text.contains("rejected")
                phase = .pushFailed(text, behind: behind && !pullFirst)
            }
            store.refreshChanges()
        }
    }

    /// "Edit Morning Walk", "Add Field Notes", "Edit About, Tags and 2 more".
    private func suggestedMessage() -> String {
        let chosen = changes.filter { picked.contains($0.id) }
        guard !chosen.isEmpty else { return "" }
        let names = chosen.map { store.title(forPath: $0.path) ?? URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }
        let verb = chosen.allSatisfy(\.isNew) ? "Add" : chosen.allSatisfy(\.isDeleted) ? "Delete" : "Edit"
        switch names.count {
        case 1: return "\(verb) \(names[0])"
        case 2: return "\(verb) \(names[0]) and \(names[1])"
        default: return "\(verb) \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

/// Colors a word diff (`git diff --word-diff=porcelain`): the changed
/// lines once, removed words struck through in red, added ones in green.
enum DiffStyle {
    static func words(_ diff: String) -> AttributedString {
        var out = AttributedString()
        var hunks = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                if hunks > 0 {
                    var gap = AttributedString("⋯\n")
                    gap.foregroundColor = .secondary
                    out += gap
                }
                hunks += 1
                continue
            }
            // The header (diff --git, index, ---/+++ lines) says nothing here.
            guard hunks > 0, let mark = line.first else { continue }
            var piece = AttributedString(String(line.dropFirst()))
            switch mark {
            case "~": piece = AttributedString("\n")
            case "+":
                piece.foregroundColor = .green
                piece.backgroundColor = .green.opacity(0.15)
            case "-":
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
            case " ": break
            default: continue
            }
            out += piece
            if out.characters.count > 8000 {
                out += AttributedString("…")
                break
            }
        }
        while let last = out.characters.last, last.isNewline { out.characters.removeLast() }
        return out.characters.isEmpty ? AttributedString("No text changes to show.") : out
    }
}
