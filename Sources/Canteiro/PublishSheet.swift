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
    @State private var selected: GitChange.ID?
    @State private var message = ""
    @State private var diff = ""
    @State private var phase: Phase = .ready
    @State private var branch = "main"

    private var changes: [GitChange] { store.changes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Publish").font(.title2.bold())
                Text("Commits to \(branch) and pushes to GitHub. Cloudflare Pages builds the site from the push.")
                    .foregroundStyle(.secondary)
            }

            if phase == .pushed {
                done
            } else {
                files
                TextField("Message", text: $message, prompt: Text("What changed"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
                footer
            }
        }
        .padding(20)
        .frame(width: 860)
        .task {
            if let site = store.siteURL { branch = await Task.detached { Git.branch(site) ?? "main" }.value }
            picked = Set(store.contentChanges.map(\.id))
            selected = changes.first { picked.contains($0.id) }?.id ?? changes.first?.id
            message = suggestedMessage()
        }
        .task(id: selected) {
            guard let site = store.siteURL, let change = changes.first(where: { $0.id == selected }) else { diff = ""; return }
            diff = await Task.detached { Git.diff(site, change) }.value
        }
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var files: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { picked.contains(change.id) },
                            set: { if $0 { picked.insert(change.id) } else { picked.remove(change.id) } }
                        )) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        StatusBadge(change: change)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.title(forPath: change.path) ?? URL(fileURLWithPath: change.path).lastPathComponent)
                                .lineLimit(1)
                            Text(change.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(change.id)
                }
            }
            .frame(width: 320)
            .disabled(isWorking)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(DiffStyle.attributed(diff))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(.background)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
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
    }

    private var done: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pushed to \(branch)").font(.headline)
                Text("Cloudflare Pages is building the site.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
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

private struct StatusBadge: View {
    let change: GitChange

    var body: some View {
        let (letter, color): (String, Color) = change.isNew ? ("A", .green) : change.isDeleted ? ("D", .red) : ("M", .orange)
        Text(letter)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(change.isNew ? "New" : change.isDeleted ? "Deleted" : "Changed")
    }
}

/// Colors a unified diff: added lines green, removed red, hunks faded.
enum DiffStyle {
    static func attributed(_ diff: String) -> AttributedString {
        guard !diff.isEmpty else { return AttributedString("No changes to show.") }
        var out = AttributedString()
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            // The header (diff --git, index, ---/+++ lines) says nothing new here.
            if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
                || line.hasPrefix("new file") || line.hasPrefix("deleted file") { continue }
            var piece = AttributedString(String(line) + "\n")
            if line.hasPrefix("+") {
                piece.foregroundColor = .green
                piece.backgroundColor = .green.opacity(0.08)
            } else if line.hasPrefix("-") {
                piece.foregroundColor = .red
                piece.backgroundColor = .red.opacity(0.08)
            } else if line.hasPrefix("@@") {
                piece.foregroundColor = .secondary
            }
            out += piece
        }
        return out
    }
}
