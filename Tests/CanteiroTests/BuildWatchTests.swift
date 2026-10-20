import Foundation
import Testing
@testable import Canteiro

/// Reading the build checks GitHub keeps on a commit.
@Suite struct BuildWatchTests {
    private func run(_ status: String, _ conclusion: String?) -> String {
        """
        {"name": "Cloudflare Pages", "status": "\(status)", "conclusion": \(conclusion.map { "\"\($0)\"" } ?? "null"),
         "details_url": "https://dash.cloudflare.com/x", "output": {"title": "Deployed successfully"}}
        """
    }

    private func checks(_ runs: [String], statuses: String = "[]") -> [BuildWatch.Check] {
        let body = #"{"total_count": \#(runs.count), "check_runs": [\#(runs.joined(separator: ","))]}"#
        return BuildWatch.checks(runs: Data(body.utf8), statuses: Data(statuses.utf8))
    }

    @Test func cloudflareGoesFromBuildingToLive() {
        #expect(BuildWatch.summary(checks([run("in_progress", nil)])) == .building(name: "Cloudflare Pages", url: URL(string: "https://dash.cloudflare.com/x")))
        #expect(BuildWatch.summary(checks([run("completed", "success")])) == .live(name: "Cloudflare Pages", url: URL(string: "https://dash.cloudflare.com/x")))
    }

    @Test func aFailedBuildSaysWhy() {
        guard case .failed(let name, let detail, _) = BuildWatch.summary(checks([run("completed", "failure")])) else {
            Issue.record("not failed"); return
        }
        #expect(name == "Cloudflare Pages")
        #expect(detail == "Deployed successfully")
    }

    /// Netlify reports statuses, newest first; an older pending one doesn't count.
    @Test func netlifyStatusesUseTheLatest() {
        let statuses = """
        [{"context": "netlify/site/deploy-preview", "state": "success", "description": "Deploy succeeded", "target_url": "https://app.netlify.com/x"},
         {"context": "netlify/site/deploy-preview", "state": "pending", "description": "Building"}]
        """
        let found = checks([], statuses: statuses)
        #expect(found.count == 1)
        #expect(BuildWatch.summary(found) == .live(name: "netlify/site/deploy-preview", url: URL(string: "https://app.netlify.com/x")))
    }

    @Test func repoFromRemote() {
        #expect(BuildWatch.repo(remote: "git@github.com:amongthestones/canteiro.git") == "amongthestones/canteiro")
        #expect(BuildWatch.repo(remote: "https://github.com/amongthestones/among-the-stones\n") == "amongthestones/among-the-stones")
        #expect(BuildWatch.repo(remote: "https://gitlab.com/a/b.git") == nil)
    }
}
