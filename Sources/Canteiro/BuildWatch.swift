import Foundation
import Observation

/// After a push, how the site's build is going, from the checks its host
/// reports to GitHub on the commit: Cloudflare Pages and Netlify both do.
/// Asks through the GitHub CLI (`gh`), which knows the account already, so
/// there's no key to set up. Without `gh`, signed in, and a GitHub remote,
/// it says nothing.
@MainActor
@Observable
final class BuildWatch {
    enum State: Equatable {
        case idle
        /// Pushed; the host hasn't reported yet, or is building.
        case building(name: String?, url: URL?)
        case live(name: String, url: URL?)
        case failed(name: String, detail: String?, url: URL?)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    /// Starts watching the commit just pushed.
    func watch(site: URL) {
        task?.cancel()
        task = Task {
            let found = await Task.detached { () -> (gh: String, repo: String, sha: String)? in
                guard let gh = Self.ghPath(), let repo = Self.repo(site), let sha = Git.head(site) else { return nil }
                return (gh, repo, sha)
            }.value
            guard let found else { return }
            var answered = false
            // A build takes a minute or two; give up quietly after 20.
            for attempt in 0..<240 {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 3 : 5))
                guard !Task.isCancelled else { return }
                let checks = await Task.detached { Self.checks(gh: found.gh, repo: found.repo, sha: found.sha) }.value
                guard let checks else {
                    // gh that isn't signed in, or no network: say nothing.
                    if !answered, attempt >= 2 { state = .idle; return }
                    continue
                }
                if !answered {
                    answered = true
                    state = .building(name: nil, url: nil)
                }
                if checks.isEmpty {
                    // Nothing reports builds for this repo.
                    if attempt >= 24 { state = .idle; return }
                    continue
                }
                state = Self.summary(checks)
                if case .building = state { continue }
                return
            }
            state = .idle
        }
    }

    func dismiss() {
        task?.cancel()
        state = .idle
    }

    // MARK: Checks

    struct Check: Equatable {
        enum Result { case running, passed, failed }
        let name: String
        let result: Result
        let detail: String?
        let url: URL?
    }

    /// All the checks together: failed if any failed, building while any
    /// runs, live once all passed.
    nonisolated static func summary(_ checks: [Check]) -> State {
        if let failed = checks.first(where: { $0.result == .failed }) {
            return .failed(name: failed.name, detail: failed.detail, url: failed.url)
        }
        if let running = checks.first(where: { $0.result == .running }) {
            return .building(name: running.name, url: running.url)
        }
        let first = checks[0]
        return .live(name: first.name, url: first.url)
    }

    /// GitHub's check runs (Cloudflare Pages) and commit statuses
    /// (Netlify) for a commit, or nil when GitHub couldn't be asked.
    nonisolated static func checks(gh: String, repo: String, sha: String) -> [Check]? {
        guard let runs = api(gh, "repos/\(repo)/commits/\(sha)/check-runs"),
              let statuses = api(gh, "repos/\(repo)/commits/\(sha)/statuses") else { return nil }
        return checks(runs: runs, statuses: statuses)
    }

    nonisolated static func checks(runs: Data, statuses: Data) -> [Check] {
        var result: [Check] = []
        let runList = (try? JSONSerialization.jsonObject(with: runs) as? [String: Any])?["check_runs"] as? [[String: Any]] ?? []
        for run in runList {
            let conclusion = run["conclusion"] as? String
            let outcome: Check.Result = run["status"] as? String != "completed" ? .running
                : ["success", "neutral", "skipped"].contains(conclusion ?? "") ? .passed : .failed
            result.append(Check(name: run["name"] as? String ?? "Build", result: outcome,
                                detail: (run["output"] as? [String: Any])?["title"] as? String,
                                url: (run["details_url"] as? String).flatMap(URL.init(string:))))
        }
        // Newest first; only each context's latest counts.
        var seen: Set<String> = []
        for status in (try? JSONSerialization.jsonObject(with: statuses) as? [[String: Any]]) ?? [] {
            let name = status["context"] as? String ?? "Build"
            guard seen.insert(name).inserted else { continue }
            let state = status["state"] as? String
            let outcome: Check.Result = state == "pending" ? .running : state == "success" ? .passed : .failed
            result.append(Check(name: name, result: outcome, detail: status["description"] as? String,
                                url: (status["target_url"] as? String).flatMap(URL.init(string:))))
        }
        return result
    }

    private nonisolated static func api(_ gh: String, _ path: String) -> Data? {
        guard let out = try? Subprocess.run(gh, ["api", path], timeout: 20), out.status == 0 else { return nil }
        return out.stdout
    }

    // MARK: Where to ask

    /// `owner/name` from an origin on GitHub, over SSH or HTTPS.
    nonisolated static func repo(remote: String) -> String? {
        let url = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = url.range(of: "github.com[:/]", options: .regularExpression) else { return nil }
        var path = String(url[range.upperBound...])
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.split(separator: "/")
        return parts.count == 2 ? parts.joined(separator: "/") : nil
    }

    private nonisolated static func repo(_ site: URL) -> String? {
        Git.remoteURL(site).flatMap { repo(remote: $0) }
    }

    nonisolated static func ghPath() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
