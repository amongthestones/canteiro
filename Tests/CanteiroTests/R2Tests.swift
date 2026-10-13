import Foundation
import Testing
@testable import Canteiro

@Suite struct R2Tests {
    /// AWS's published Signature V4 example for S3 (GET Object with a Range
    /// header), so the signer is checked against Amazon's own numbers.
    @Test func signatureMatchesAWSExample() {
        let date = ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z")!
        let headers = SigV4.sign(
            method: "GET", path: "/test.txt", query: "",
            headers: ["Host": "examplebucket.s3.amazonaws.com", "Range": "bytes=0-9"],
            payload: Data(),
            accessKeyID: "AKIAIOSFODNN7EXAMPLE", secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "us-east-1", date: date)
        #expect(headers["authorization"] == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    @Test func pathSegmentsAreEncoded() {
        #expect(SigV4.encode("Café à Noite.webp") == "Caf%C3%A9%20%C3%A0%20Noite.webp")
        #expect(SigV4.encode("myshow-001.mp3") == "myshow-001.mp3")
    }

    @Test func pastedKeysAreTrimmed() {
        #expect(R2Settings.trimmed("  \"abc123\"\n") == "abc123")
    }

    @Test func keysOfTheWrongShapeAreFlagged() {
        #expect(R2Settings.problem(String(repeating: "a1", count: 16), length: 32) == nil)
        #expect(R2Settings.problem("", length: 32) == nil, "empty is just not set")
        #expect(R2Settings.problem(String(repeating: "a", count: 31), length: 32)?.contains("31") == true)
        #expect(R2Settings.problem(String(repeating: "z", count: 32), length: 32)?.contains("a to f") == true)
    }
}

@Suite struct SiteCheckTests {
    @Test func findsGitAndSaysWhatsMissing() async {
        let check = await SiteCheck.run(site: nil)
        #expect(check.tools.map(\.name) == ["Node", "git", "cwebp"])
        #expect(check.tools.first { $0.name == "git" }?.found != nil)
        #expect(check.tools.allSatisfy { !$0.fix.isEmpty && !$0.needed.isEmpty })
    }

    @Test(.enabled(if: SiteTests.hasSite))
    func readsTheSitesRemote() async {
        let check = await SiteCheck.run(site: SiteTests.site)
        #expect(check.tools.contains { $0.name == "Site packages" && $0.found != nil })
        #expect(check.branch != nil)
    }
}

