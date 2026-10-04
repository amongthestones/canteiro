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
        #expect(SigV4.encode("Cemitério à Eirexe.webp") == "Cemit%C3%A9rio%20%C3%A0%20Eirexe.webp")
        #expect(SigV4.encode("corrixeme-001.mp3") == "corrixeme-001.mp3")
    }
}
