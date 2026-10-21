import Foundation

/// A changed file in the site's repo.
struct GitChange: Identifiable, Hashable, Sendable {
    /// From `git status`: M modified, A added, D deleted, R renamed, ?? new.
    let code: String
    let path: String
    var id: String { path }

    var isNew: Bool { code == "??" || code.contains("A") }
    var isDeleted: Bool { code.contains("D") }
}

/// The git calls Publish needs, through the system git.
enum Git {
    enum Failure: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let message): return message }
        }
    }

    static let git = "/usr/bin/git"

    static func status(_ site: URL) throws -> [GitChange] {
        let out = try run(site, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        var changes: [GitChange] = []
        var fields = out.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = fields.popFirst(), entry.count > 3 {
            let code = entry.prefix(2).trimmingCharacters(in: .whitespaces)
            changes.append(GitChange(code: code, path: String(entry.dropFirst(3))))
            // A rename lists its old path next; it's part of the same change.
            if code.hasPrefix("R") || code.hasPrefix("C") { _ = fields.popFirst() }
        }
        return changes
    }

    static func branch(_ site: URL) -> String? {
        try? run(site, ["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Local branches, then branches only on GitHub, for the branch menu.
    static func branches(_ site: URL) -> (local: [String], remote: [String]) {
        func names(_ arguments: [String]) -> [String] {
            ((try? run(site, arguments)) ?? "").split(separator: "\n").map(String.init)
        }
        let local = names(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
        let remote = names(["for-each-ref", "--format=%(refname:lstrip=3)", "refs/remotes/origin"])
            .filter { $0 != "HEAD" && !local.contains($0) }
        return (local, remote)
    }

    /// Checks out a branch. One only on GitHub becomes a local branch that
    /// tracks it, so Publish pushes back to it.
    static func switchTo(_ site: URL, _ branch: String) throws {
        _ = try run(site, ["switch", branch])
    }

    /// Starts a branch from another, switches to it and pushes it, so it
    /// has a preview build and Publish can push to it.
    static func createBranch(_ site: URL, _ branch: String, from base: String) throws {
        _ = try run(site, ["switch", "-c", branch, base])
        _ = try run(site, ["push", "-u", "origin", branch], timeout: 90)
    }

    /// The last commit's full hash.
    static func head(_ site: URL) -> String? {
        try? run(site, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where Publish pushes to.
    static func remoteURL(_ site: URL) -> String? {
        try? run(site, ["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The change as a word diff (`--word-diff=porcelain`), which reads
    /// better than whole lines for prose. A new file shows as all added.
    static func diff(_ site: URL, _ change: GitChange) -> String {
        if change.code == "??" {
            return (try? run(site, ["diff", "--word-diff=porcelain", "--no-index", "--", "/dev/null", change.path], allowFailure: true)) ?? ""
        }
        return (try? run(site, ["diff", "--word-diff=porcelain", "HEAD", "--", change.path])) ?? ""
    }

    /// Whether the last commit has this file.
    static func isCommitted(_ site: URL, _ path: String) -> Bool {
        (try? run(site, ["cat-file", "-e", "HEAD:" + path])) != nil
    }

    /// Puts a file back as the last commit has it, after moving the version
    /// on disk to the Trash. A file the last commit doesn't have just goes
    /// to the Trash.
    static func discard(_ site: URL, _ change: GitChange,
                        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let file = site.appending(path: change.path)
        let committed = isCommitted(site, change.path)
        if FileManager.default.fileExists(atPath: file.path) { try trash(file) }
        if committed {
            try run(site, ["restore", "--source=HEAD", "--staged", "--worktree", "--", change.path])
        } else {
            try run(site, ["rm", "--cached", "--quiet", "--ignore-unmatch", "--", change.path])
        }
    }

    /// Commits exactly these paths (nothing else that's staged) and pushes.
    static func commitAndPush(_ site: URL, paths: [String], message: String) throws {
        try commit(site, paths: paths, message: message)
        try push(site)
    }

    static func commit(_ site: URL, paths: [String], message: String) throws {
        _ = try run(site, ["add", "-A", "--"] + paths)
        _ = try run(site, ["commit", "--only", "-m", message, "--"] + paths)
    }

    static func push(_ site: URL) throws {
        _ = try run(site, ["push"], timeout: 90)
    }

    /// Takes GitHub's newer commits under ours, keeping any other work in
    /// progress aside while it does.
    static func pullRebase(_ site: URL) throws {
        _ = try run(site, ["pull", "--rebase", "--autostash"], timeout: 90)
    }

    @discardableResult
    private static func run(_ site: URL, _ arguments: [String], timeout: TimeInterval = 20, allowFailure: Bool = false) throws -> String {
        // No prompts: a push that needs a password fails instead of hanging.
        let out = try Subprocess.run(git, ["-C", site.path] + arguments, timeout: timeout,
                                     environment: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"])
        guard out.status == 0 || allowFailure else {
            let detail = (out.stderrString + out.stdoutString).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(detail.isEmpty ? "git \(arguments.first ?? "") failed." : detail)
        }
        return out.stdoutString
    }
}
