import CryptoKit
import Foundation
import Security

/// The Cloudflare account uploads use. The keys live in the Keychain, the
/// account ID in the app's settings. The bucket and public address are the
/// site's, in its canteiro.json.
enum R2Settings {
    static var accountID: String {
        UserDefaults.standard.string(forKey: "r2AccountID") ?? ""
    }

    static var accessKeyID: String { Keychain.read("accessKeyID") ?? "" }

    static var secretAccessKey: String { Keychain.read("secretAccessKey") ?? "" }

    static var isComplete: Bool {
        !accountID.isEmpty && !accessKeyID.isEmpty && !secretAccessKey.isEmpty
    }

    /// Saves all three, trimmed. Throws when the Keychain won't take a key,
    /// so that shows here and not as a failed upload later.
    static func save(accountID: String, accessKeyID: String, secret: String) throws {
        UserDefaults.standard.set(trimmed(accountID), forKey: "r2AccountID")
        try Keychain.write("accessKeyID", trimmed(accessKeyID))
        try Keychain.write("secretAccessKey", trimmed(secret))
    }

    /// Pasted keys often bring a space, a line break or quotes with them.
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))
    }

    /// What's off about a value, judged by the shape Cloudflare gives it:
    /// the account ID and key ID are 32 hex characters, the secret 64.
    /// A warning, not a block, in case Cloudflare changes them.
    static func problem(_ value: String, length: Int) -> String? {
        let value = trimmed(value)
        guard !value.isEmpty else { return nil }
        if value.contains(where: { !$0.isHexDigit }) { return "Cloudflare's are letters a to f and digits only." }
        if value.count != length { return "Cloudflare's are \(length) characters; this is \(value.count)." }
        return nil
    }

    /// The last Save and Check: when, against which bucket and keys, and
    /// what R2 said. Kept so Settings opens knowing whether uploads work.
    struct Check: Codable, Equatable {
        var date: Date
        var bucket: String
        var accountID: String
        var accessKeyID: String
        /// Nil when R2 took it.
        var error: String?
    }

    static var lastCheck: Check? {
        get { UserDefaults.standard.data(forKey: "r2LastCheck").flatMap { try? JSONDecoder().decode(Check.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "r2LastCheck") }
    }
}

/// The R2 keys, kept in the login keychain.
enum Keychain {
    private static let service = "com.amongthestones.canteiro.r2"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "The Keychain didn't save the key: \(reason)"
        }
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Replaces the key, or removes it when the value is empty.
    static func write(_ account: String, _ value: String) throws {
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        if value.isEmpty {
            let status = SecItemDelete(match as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard read(account) == value else { throw Failure(status: errSecDecode) }
    }
}

/// Uploads to R2 through its S3-compatible API, signed with AWS Signature V4.
struct R2Client: Sendable {
    enum Failure: LocalizedError {
        case notSetUp
        case rejected(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSetUp: return "R2 isn't set up. Add the account ID and keys in Settings › Uploads (⌘,)."
            case .rejected(let code, let body): return "R2 said \(code): \(Self.message(in: body))"
            }
        }

        /// R2 answers in S3's XML. Its Message says what was wrong (a key of
        /// the wrong length, a missing bucket), so show that, not the XML.
        static func message(in body: String) -> String {
            func tag(_ name: String) -> String? {
                guard let start = body.range(of: "<\(name)>"), let end = body.range(of: "</\(name)>", range: start.upperBound..<body.endIndex) else { return nil }
                return String(body[start.upperBound..<end.lowerBound])
            }
            switch (tag("Code"), tag("Message")) {
            case let (code?, message?): return "\(code). \(message)"
            case let (code?, nil): return code
            default: return body
            }
        }
    }

    let accountID: String
    let bucket: String
    let accessKeyID: String
    let secretAccessKey: String

    static func fromSettings(bucket: String) throws -> R2Client {
        guard R2Settings.isComplete else { throw Failure.notSetUp }
        return R2Client(accountID: R2Settings.accountID, bucket: bucket,
                        accessKeyID: R2Settings.accessKeyID, secretAccessKey: R2Settings.secretAccessKey)
    }

    /// Puts a file at `key` (uploads/2026/10/photo.webp), reporting progress
    /// from 0 to 1.
    func put(_ file: URL, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let data = try Data(contentsOf: file)
        let host = "\(accountID).r2.cloudflarestorage.com"
        let path = "/" + bucket + "/" + key.split(separator: "/").map { SigV4.encode(String($0)) }.joined(separator: "/")
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = "PUT"
        let headers = ["host": host, "content-type": contentType, "content-length": String(data.count)]
        let signed = SigV4.sign(method: "PUT", path: path, query: "", headers: headers, payload: data,
                                accessKeyID: accessKeyID, secret: secretAccessKey, region: "auto", date: .now)
        for (name, value) in signed where name != "host" && name != "content-length" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let watcher = UploadProgress(report: progress)
        let (body, response) = try await URLSession.shared.upload(for: request, from: data, delegate: watcher)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.rejected(code, String(decoding: body, as: UTF8.self))
        }
        progress(1)
    }

    /// Lists one object: a cheap check that the account, bucket and keys work.
    func check() async throws {
        let host = "\(accountID).r2.cloudflarestorage.com"
        let path = "/" + bucket
        let query = "list-type=2&max-keys=1"
        var request = URLRequest(url: URL(string: "https://\(host)\(path)?\(query)")!)
        let signed = SigV4.sign(method: "GET", path: path, query: query, headers: ["host": host], payload: Data(),
                                accessKeyID: accessKeyID, secret: secretAccessKey, region: "auto", date: .now)
        for (name, value) in signed where name != "host" { request.setValue(value, forHTTPHeaderField: name) }
        let (body, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.rejected(code, String(decoding: body, as: UTF8.self))
        }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

/// AWS Signature Version 4, as S3 and R2 use it.
enum SigV4 {
    /// The headers to send: the ones given, plus x-amz-date,
    /// x-amz-content-sha256 and Authorization.
    static func sign(method: String, path: String, query: String, headers: [String: String], payload: Data,
                     accessKeyID: String, secret: String, region: String, service: String = "s3", date: Date) -> [String: String] {
        let stamp = formatted(date, "yyyyMMdd'T'HHmmss'Z'")
        let day = String(stamp.prefix(8))
        let payloadHash = hex(SHA256.hash(data: payload))
        var all = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) })
        all["x-amz-date"] = stamp
        all["x-amz-content-sha256"] = payloadHash

        let names = all.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(all[$0]!)\n" }.joined()
        let signedHeaders = names.joined(separator: ";")
        let canonicalQuery = query.split(separator: "&").map(String.init).sorted().joined(separator: "&")
        let canonicalRequest = [method, path, canonicalQuery, canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")

        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", stamp, scope, hex(SHA256.hash(data: Data(canonicalRequest.utf8)))].joined(separator: "\n")

        var key = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        for part in [day, region, service, "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))
        all["authorization"] = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return all
    }

    /// Percent-encodes a path segment the way S3 expects (RFC 3986 unreserved kept).
    static func encode(_ segment: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f.string(from: date)
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
