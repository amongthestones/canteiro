import Foundation
import Testing
@testable import Canteiro

/// Git against a throwaway repo and a local "GitHub". Never the real remote.
@Suite struct GitTests {
    private func sh(_ dir: URL, _ args: [String]) throws {
        let out = try Subprocess.run(Git.git, ["-C", dir.path] + args, timeout: 20)
        #expect(out.status == 0, "\(args): \(out.stderrString)")
    }

    /// A bare remote, and a clone of it with one commit, pushed.
    private func repo() throws -> (work: URL, remote: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "canteiro-git-\(UUID().uuidString)")
        let remote = root.appending(path: "remote.git")
        let work = root.appending(path: "work")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try sh(root, ["init", "-q", "--bare", "-b", "main", remote.path])
        try sh(root, ["clone", "-q", remote.path, work.path])
        try sh(work, ["config", "user.email", "test@example.com"])
        try sh(work, ["config", "user.name", "Test"])
        try "title: One\n".write(to: work.appending(path: "post.yaml"), atomically: true, encoding: .utf8)
        try sh(work, ["add", "-A"])
        try sh(work, ["commit", "-q", "-m", "First"])
        try sh(work, ["push", "-q", "-u", "origin", "main"])
        return (work, remote)
    }

    @Test func statusSeesEditsAndNewFiles() throws {
        let (work, _) = try repo()
        try "title: Two\n".write(to: work.appending(path: "post.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: work.appending(path: "src"), withIntermediateDirectories: true)
        try "new\n".write(to: work.appending(path: "src/new file.md"), atomically: true, encoding: .utf8)
        let changes = try Git.status(work)
        #expect(changes.map(\.path).sorted() == ["post.yaml", "src/new file.md"])
        #expect(changes.first { $0.path == "src/new file.md" }?.isNew == true)
        #expect(Git.diff(work, changes.first { $0.path == "post.yaml" }!).contains("+Two"))
        #expect(Git.diff(work, changes.first { $0.path == "src/new file.md" }!).contains("+new"))
    }

    @Test func listsAndSwitchesBranches() throws {
        let (work, _) = try repo()
        try sh(work, ["switch", "-q", "-c", "reading"])
        try sh(work, ["push", "-q", "-u", "origin", "reading"])
        try sh(work, ["switch", "-q", "main"])
        try sh(work, ["branch", "-q", "-D", "reading"])

        // Pushed but deleted here: listed as only on GitHub.
        var found = Git.branches(work)
        #expect(found.local == ["main"])
        #expect(found.remote == ["reading"])

        try Git.switchTo(work, "reading")
        #expect(Git.branch(work) == "reading")
        found = Git.branches(work)
        #expect(found.local.sorted() == ["main", "reading"])
        #expect(found.remote.isEmpty)
    }

    @Test func makesAndPushesABranch() throws {
        let (work, remote) = try repo()
        try Git.createBranch(work, "staging", from: "main")
        #expect(Git.branch(work) == "staging")
        let pushed = try Subprocess.run(Git.git, ["-C", remote.path, "branch", "--list", "staging"], timeout: 10).stdoutString
        #expect(pushed.contains("staging"))
        // Tracks GitHub's copy, so a plain push goes there.
        let upstream = try Subprocess.run(Git.git, ["-C", work.path, "rev-parse", "--abbrev-ref", "@{u}"], timeout: 10).stdoutString
        #expect(upstream.trimmingCharacters(in: .whitespacesAndNewlines) == "origin/staging")
    }

    @Test func publishesOnlyThePickedFiles() throws {
        let (work, remote) = try repo()
        try "title: Two\n".write(to: work.appending(path: "post.yaml"), atomically: true, encoding: .utf8)
        try "code in progress\n".write(to: work.appending(path: "code.ts"), atomically: true, encoding: .utf8)
        try sh(work, ["add", "code.ts"]) // staged by hand, must not ride along

        try Git.commitAndPush(work, paths: ["post.yaml"], message: "Edit One")

        let pushed = try Subprocess.run(Git.git, ["-C", remote.path, "log", "-1", "--name-only", "--format=%s"], timeout: 10).stdoutString
        #expect(pushed.contains("Edit One"))
        #expect(pushed.contains("post.yaml"))
        #expect(!pushed.contains("code.ts"))
        #expect(try Git.status(work).map(\.path) == ["code.ts"])
    }

    @Test func aRejectedPushSaysWhy() throws {
        let (work, remote) = try repo()
        // Someone else pushes first.
        let other = remote.deletingLastPathComponent().appending(path: "other")
        try sh(remote.deletingLastPathComponent(), ["clone", "-q", remote.path, other.path])
        try sh(other, ["config", "user.email", "o@example.com"])
        try sh(other, ["config", "user.name", "Other"])
        try "elsewhere\n".write(to: other.appending(path: "other.yaml"), atomically: true, encoding: .utf8)
        try sh(other, ["add", "-A"])
        try sh(other, ["commit", "-q", "-m", "Other"])
        try sh(other, ["push", "-q"])

        try "title: Two\n".write(to: work.appending(path: "post.yaml"), atomically: true, encoding: .utf8)
        #expect(throws: Git.Failure.self) { try Git.commitAndPush(work, paths: ["post.yaml"], message: "Edit") }

        try Git.pullRebase(work)
        try Git.push(work)
        let log = try Subprocess.run(Git.git, ["-C", remote.path, "log", "--format=%s"], timeout: 10).stdoutString
        #expect(log.split(separator: "\n") == ["Edit", "Other", "First"])
    }

    /// Discarding puts an edit back and removes a new file, and the
    /// discarded versions go to the trash, never just away.
    @Test func discardPutsFilesBack() throws {
        let (work, _) = try repo()
        try "title: Two\n".write(to: work.appending(path: "post.yaml"), atomically: true, encoding: .utf8)
        try "new\n".write(to: work.appending(path: "new.md"), atomically: true, encoding: .utf8)
        var trashed: [String] = []
        let trash: (URL) throws -> Void = { url in
            trashed.append(try String(contentsOf: url, encoding: .utf8))
            try FileManager.default.removeItem(at: url)
        }
        for change in try Git.status(work) { try Git.discard(work, change, trash: trash) }
        #expect(try Git.status(work).isEmpty)
        #expect(try String(contentsOf: work.appending(path: "post.yaml"), encoding: .utf8) == "title: One\n")
        #expect(Set(trashed) == ["title: Two\n", "new\n"])
    }
}

@Suite struct DiffStyleTests {
    @Test func wordDiffShowsTheLineOnce() {
        let porcelain = "diff --git a/p.md b/p.md\n@@ -1 +1 @@\n I also\n-help \n run a space\n-in town\n~\n"
        let out = DiffStyle.words(porcelain)
        #expect(String(out.characters) == "I alsohelp run a spacein town")
        let removed = out.runs.filter { $0.strikethroughStyle != nil }.map { String(out[$0.range].characters) }
        #expect(removed == ["help ", "in town"])
    }
}
