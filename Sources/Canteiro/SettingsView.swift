import AppKit
import SwiftUI

/// Canteiro › Settings. General shows what Canteiro found: the open site,
/// its config files, and the tools it runs, each with what to do when it's
/// missing. Uploads holds the Cloudflare account and keys.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Uploads", systemImage: "icloud.and.arrow.up") {
                UploadSettings()
            }
        }
        .frame(width: 560)
    }
}

// MARK: General

/// What Canteiro found on this Mac and in the site, checked when the tab
/// opens and on Check Again.
struct SiteCheck: Sendable, Equatable {
    struct Tool: Sendable, Equatable, Identifiable {
        let name: String
        /// What was found (a version, a path), or nil when it wasn't.
        let found: String?
        /// What to do when it's missing.
        let fix: String
        /// What goes without it.
        let needed: String
        var id: String { name }
    }

    var tools: [Tool] = []
    /// Where Publish pushes, or nil without a remote.
    var remote: String?
    var branch: String?

    static func run(site: URL?) async -> SiteCheck {
        await Task.detached(priority: .userInitiated) {
            var check = SiteCheck()
            let node = NodeLocator.path()
            check.tools.append(Tool(name: "Node", found: node.map { version($0, ["--version"]) ?? $0 },
                                    fix: "Install it with Homebrew: brew install node",
                                    needed: "Canteiro reads keystatic.config.ts with it, so no site opens without it."))
            let gitVersion = version("/usr/bin/git", ["--version"]).map { $0.replacingOccurrences(of: "git version ", with: "") }
            check.tools.append(Tool(name: "git", found: gitVersion,
                                    fix: "Install Apple's command line tools: xcode-select --install",
                                    needed: "Publish commits and pushes with it."))
            let cwebp = PhotoProcessor.cwebpPath
            check.tools.append(Tool(name: "cwebp", found: cwebp.map { version($0, ["-version"]) ?? $0 },
                                    fix: "Install it with Homebrew: brew install webp",
                                    needed: "Photos dropped into the body are made WebP with it."))
            if let site {
                let installed = FileManager.default.fileExists(atPath: site.appending(path: "node_modules/@keystatic/core").path)
                check.tools.append(Tool(name: "Site packages", found: installed ? "Installed" : nil,
                                        fix: "In the site's folder, run: npm install",
                                        needed: "keystatic.config.ts is read through the site's own packages."))
                check.remote = git(site, ["remote", "get-url", "origin"])
                check.branch = git(site, ["rev-parse", "--abbrev-ref", "HEAD"])
            }
            return check
        }.value
    }

    /// The first line a tool prints about itself.
    nonisolated private static func version(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path),
              let out = try? Subprocess.run(path, arguments, timeout: 5), out.status == 0 else { return nil }
        let line = (out.stdoutString + out.stderrString).split(separator: "\n").first.map(String.init)
        return line?.trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func git(_ site: URL, _ arguments: [String]) -> String? {
        guard let out = try? Subprocess.run(Git.git, ["-C", site.path] + arguments, timeout: 5), out.status == 0 else { return nil }
        let text = out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private struct GeneralSettings: View {
    @Environment(SiteStore.self) private var store
    @Environment(DraftInbox.self) private var inbox
    @State private var check: SiteCheck?
    @State private var checking = false

    var body: some View {
        Form {
            site
            if store.siteURL != nil, store.config.inbox != nil {
                inboxSection
            }
            tools
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: store.siteURL) { await recheck() }
    }

    @ViewBuilder
    private var site: some View {
        Section {
            if let url = store.siteURL {
                LabeledContent("Folder") {
                    HStack {
                        Text(url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link)
                    }
                }
                LabeledContent("keystatic.config.ts") { keystatic }
                LabeledContent(SiteConfig.fileName) { siteConfig(url) }
                LabeledContent("Publishes to") { publishing }
            } else {
                LabeledContent("No site open") {
                    Button("Open Site…") { store.chooseSite() }
                }
            }
        } header: {
            Text("Site")
        }
    }

    @ViewBuilder
    private var keystatic: some View {
        switch store.phase {
        case .ready:
            let items = store.schema?.items ?? []
            let collections = items.filter { $0.kind == .collection }.count
            Status(ok: true, text: "\(collections) \(collections == 1 ? "collection" : "collections"), \(items.count - collections) \(items.count - collections == 1 ? "singleton" : "singletons")")
        case .failed(let message):
            Status(ok: false, text: message)
        default:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func siteConfig(_ site: URL) -> some View {
        if let problem = store.configProblem {
            Status(ok: false, text: problem)
        } else if !FileManager.default.fileExists(atPath: site.appending(path: SiteConfig.fileName).path) {
            Status(ok: nil, text: "None, so the inbox, uploads and MP3 drops are off. The canteiro.json page in the docs shows what goes in it.")
        } else {
            let config = store.config
            let parts = [config.inbox.map { _ in "inbox" }, config.uploads.map { _ in "uploads" },
                         config.podcasts.map { _ in "podcasts" }].compactMap { $0 }
            Status(ok: true, text: parts.isEmpty ? "Loaded" : "Loaded: " + parts.joined(separator: ", "))
        }
    }

    @ViewBuilder
    private var publishing: some View {
        if let check {
            if let remote = check.remote {
                Status(ok: true, text: remote.replacing(/^https:\/\/|^git@|\.git$/, with: "") + (check.branch.map { ", \($0)" } ?? ""))
            } else {
                Status(ok: false, text: "No remote named origin, so Publish can commit but not push.")
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var inboxSection: some View {
        Section {
            LabeledContent("Folder") {
                VStack(alignment: .trailing, spacing: 3) {
                    if let folder = inbox.folder {
                        Text(folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                    }
                    if let problem = inbox.problem {
                        Status(ok: false, text: problem)
                    }
                    Button("Choose…") { inbox.chooseFolder() }
                        .buttonStyle(.link)
                }
            }
        } header: {
            Text("Inbox")
        } footer: {
            Text("Drafts from \(inbox.app). A folder chosen here is this Mac's and wins over the site's.")
                .foregroundStyle(.secondary)
        }
    }

    private var tools: some View {
        Section {
            if let check {
                ForEach(check.tools) { tool in
                    LabeledContent {
                        if let found = tool.found {
                            Status(ok: true, text: found)
                        } else {
                            VStack(alignment: .trailing, spacing: 2) {
                                Status(ok: false, text: "Not found")
                                Text(tool.fix).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    } label: {
                        Text(tool.name)
                        Text(tool.needed)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            HStack {
                Text("Tools")
                Spacer()
                Button("Check Again") { Task { await recheck() } }
                    .buttonStyle(.link)
                    .disabled(checking)
                    .textCase(nil)
            }
        }
    }

    private func recheck() async {
        checking = true
        check = await SiteCheck.run(site: store.siteURL)
        checking = false
    }
}

/// A check mark, a warning or a note, and what it's about.
private struct Status: View {
    /// Nil for a note: nothing wrong, nothing found.
    let ok: Bool?
    let text: String

    var body: some View {
        Label {
            Text(text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            switch ok {
            case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case false?: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case nil: Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Uploads

/// The Cloudflare account uploads use. Keys are stored in the Keychain. The
/// bucket and address are the site's, in its canteiro.json, and only shown
/// here.
private struct UploadSettings: View {
    @Environment(SiteStore.self) private var store
    @State private var accountID = R2Settings.accountID
    @State private var accessKeyID = R2Settings.accessKeyID
    @State private var secret = R2Settings.secretAccessKey
    @State private var lastCheck = R2Settings.lastCheck
    @State private var checking = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                field("Account ID", text: $accountID, prompt: "From the R2 overview page", length: 32)
                if let uploads = store.config.uploads {
                    LabeledContent("Bucket", value: uploads.bucket)
                    LabeledContent("Public address", value: uploads.publicBase)
                }
            } header: {
                Text("Cloudflare R2")
            } footer: {
                Text(store.config.uploads == nil
                     ? "\(store.siteName) has no uploads block in \(SiteConfig.fileName), so photo and MP3 drops are off."
                     : "The bucket and address come from \(store.siteName)'s \(SiteConfig.fileName).")
                    .foregroundStyle(.secondary)
            }
            Section {
                field("Access key ID", text: $accessKeyID, length: 32)
                field("Secret access key", text: $secret, length: 64, secure: true)
            } header: {
                Text("API token")
            } footer: {
                Text("An R2 API token with Object Read & Write on this bucket. Kept in your Keychain.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    status
                    Spacer()
                    Button("Save and Check") { saveAndCheck() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(checking || store.config.uploads == nil)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String? = nil, length: Int, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if secure {
                SecureField(title, text: text, prompt: prompt.map { Text($0) })
            } else {
                TextField(title, text: text, prompt: prompt.map { Text($0) })
            }
            if let problem = R2Settings.problem(text.wrappedValue, length: length) {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// The last check, if it was of these keys and this bucket. Edited keys
    /// haven't been checked yet.
    @ViewBuilder
    private var status: some View {
        if checking {
            ProgressView().controlSize(.small)
        } else if let saveError {
            Label(saveError, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
        } else if let lastCheck, let bucket = store.config.uploads?.bucket, lastCheck.bucket == bucket,
                  lastCheck.accountID == R2Settings.trimmed(accountID), lastCheck.accessKeyID == R2Settings.trimmed(accessKeyID),
                  R2Settings.trimmed(secret) == R2Settings.secretAccessKey {
            let when = lastCheck.date.formatted(.relative(presentation: .named))
            if let error = lastCheck.error {
                Label("\(error) (checked \(when))", systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
            } else {
                Label("Connected to \(bucket), checked \(when)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else if R2Settings.isComplete || !accountID.isEmpty {
            Text("Not checked yet").foregroundStyle(.secondary)
        }
    }

    private func saveAndCheck() {
        saveError = nil
        do {
            try R2Settings.save(accountID: accountID, accessKeyID: accessKeyID, secret: secret)
        } catch {
            saveError = error.localizedDescription
            return
        }
        accountID = R2Settings.accountID
        accessKeyID = R2Settings.accessKeyID
        secret = R2Settings.secretAccessKey
        guard let bucket = store.config.uploads?.bucket else { return }
        checking = true
        Task {
            var result = R2Settings.Check(date: .now, bucket: bucket, accountID: accountID, accessKeyID: accessKeyID)
            do {
                try await R2Client.fromSettings(bucket: bucket).check()
            } catch {
                result.error = error.localizedDescription
            }
            R2Settings.lastCheck = result
            lastCheck = result
            checking = false
        }
    }
}
