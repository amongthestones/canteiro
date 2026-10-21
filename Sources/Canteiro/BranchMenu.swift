import SwiftUI

/// The checked-out branch, and a menu to switch to another one. Branches
/// only on GitHub are listed apart; picking one checks it out here. The one
/// branch it can make is staging.
struct BranchMenu: View {
    @Environment(SiteStore.self) private var store
    @State private var local: [String] = []
    @State private var remote: [String] = []

    var body: some View {
        Menu {
            ForEach(local, id: \.self) { name in
                Toggle(name, isOn: Binding(get: { name == store.branch }, set: { _ in pick(name) }))
            }
            if !remote.isEmpty {
                Section("Only on GitHub") {
                    ForEach(remote, id: \.self) { name in
                        Button(name) { pick(name) }
                    }
                }
            }
            if !local.isEmpty, !(local + remote).contains(SiteStore.stagingBranch) {
                Divider()
                Button("Make a Staging Branch") {
                    Task { await store.makeStagingBranch() }
                }
                .help("Starts a staging branch from main and pushes it, for trying things on a preview before they go live")
            }
        } label: {
            Label(store.branch ?? "Branch", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .help("Switch branch. Publish commits to the branch shown here.")
        .disabled(store.branch == nil)
        // The branch changes on a switch, and on a fetch or switch made in
        // Terminal, which refreshChanges picks up.
        .task(id: "\(store.branch ?? "")|\(store.changes.count)") { await list() }
    }

    private func list() async {
        guard let site = store.siteURL else { return }
        let found = await Task.detached { Git.branches(site) }.value
        local = found.local
        remote = found.remote
    }

    private func pick(_ name: String) {
        Task { await store.switchBranch(to: name) }
    }
}
