import Foundation

/// What Canteiro knows about one site beyond its Keystatic config, read from
/// canteiro.json at the site's root. Everything is optional: a site without
/// the file gets plain Canteiro (standard markdown, no inbox, no MP3
/// import), and each block turns one feature on.
struct SiteConfig: Codable, Sendable, Equatable {
    static let fileName = "canteiro.json"

    /// A writing app's folder whose files can be imported as entries.
    struct Inbox: Codable, Sendable, Equatable {
        /// `~` is the home folder.
        var folder: String
        /// The collection drafts become entries of.
        var importInto: String
        /// The writing app's name, for the window's wording.
        var app: String?
    }

    /// Where dropped photos and MP3s go. The account and keys are the
    /// Mac's, in Settings; the bucket and address are the site's.
    struct Uploads: Codable, Sendable, Equatable {
        var bucket: String
        var publicBase: String
        /// Folders for photos and audio, with {yyyy} {mm} and {show}.
        var photos: String?
        var audio: String?
    }

    /// Collections of podcast episodes, which take MP3 drops.
    struct Podcasts: Codable, Sendable, Equatable {
        /// Collection keys; `*` matches any run of characters.
        var collections: [String]
        var fields: Fields?
        /// The guid a new episode gets, from {show} and {number}.
        var guid: String?

        struct Fields: Codable, Sendable, Equatable {
            var audio: String?
            var number: String?
            var guid: String?
            var duration: String?
        }
    }

    /// Markdown beyond the standard that the site's plugins understand.
    enum Syntax: String, Codable, Sendable, CaseIterable {
        /// ==text==
        case highlight
        /// [^a note], iA Writer's inline footnotes
        case inlineFootnotes
        /// ^^^text^^^
        case callouts
        /// {{TOC}}
        case toc
    }

    var inbox: Inbox?
    var uploads: Uploads?
    var podcasts: Podcasts?
    var syntax: Set<Syntax>?

    /// The site's file, or the empty config when there isn't one. A file
    /// that doesn't parse throws, so the problem can be shown.
    static func load(site: URL) throws -> SiteConfig {
        let url = site.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return SiteConfig() }
        do {
            return try JSONDecoder().decode(SiteConfig.self, from: Data(contentsOf: url))
        } catch let error as DecodingError {
            throw Failure.invalid(Self.describe(error))
        }
    }

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return "\(SiteConfig.fileName): \(reason)" }
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "\(path(context).isEmpty ? "" : path(context) + ": ")missing \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return path(context).isEmpty ? "not valid JSON" : "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: Answers the app asks

    var extras: Set<Syntax> { syntax ?? [] }

    var inboxFolder: URL? { inboxFolder(site: nil) }

    /// A relative folder (inbox/) is inside the site.
    func inboxFolder(site: URL?) -> URL? {
        guard let folder = inbox?.folder else { return nil }
        let path = NSString(string: folder).expandingTildeInPath
        if let site, !path.hasPrefix("/") { return site.appending(path: path, directoryHint: .isDirectory) }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    func isEpisodes(_ key: String) -> Bool {
        podcasts?.collections.contains { Self.matches(key, $0) } ?? false
    }

    /// Field names in an episode collection, with the defaults Keystatic
    /// sites tend to use.
    var audioField: String { podcasts?.fields?.audio ?? "audioUrl" }
    var numberField: String { podcasts?.fields?.number ?? "episodeNumber" }
    var guidField: String { podcasts?.fields?.guid ?? "guid" }
    var durationField: String { podcasts?.fields?.duration ?? "duration" }

    func guid(show: String, number: Int) -> String {
        Self.fill(podcasts?.guid ?? "{show}-{number}", ["show": show, "number": String(number)])
    }

    /// The folder a photo goes in, from the date it's added.
    func photoFolder(date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        return Self.folder(uploads?.photos ?? "uploads/{yyyy}/{mm}/",
                           ["yyyy": String(format: "%04d", parts.year!), "mm": String(format: "%02d", parts.month!)])
    }

    func audioFolder(show: String) -> String {
        Self.folder(uploads?.audio ?? "podcasts/{show}/", ["show": show])
    }

    func publicURL(for key: String) -> String? {
        uploads.map { $0.publicBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + key }
    }

    static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    private static func folder(_ template: String, _ values: [String: String]) -> String {
        let path = fill(template, values).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "" : path + "/"
    }

    static func matches(_ key: String, _ pattern: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map { NSRegularExpression.escapedPattern(for: String($0)) }
        return key.range(of: "^" + parts.joined(separator: ".*") + "$", options: .regularExpression) != nil
    }
}
