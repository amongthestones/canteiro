import AppKit
import Foundation
import Testing
@testable import Canteiro

@Suite struct SiteConfigTests {
    private let json = """
    {
      "inbox": { "folder": "~/Drafts/Blog", "importInto": "posts", "app": "iA Writer" },
      "uploads": { "bucket": "b", "publicBase": "https://media.example.com/", "photos": "img/{yyyy}/", "audio": "audio/{show}" },
      "podcasts": { "collections": ["episodes-*"], "guid": "{show}-ep{number}" },
      "syntax": ["highlight", "toc"]
    }
    """

    private func site(_ text: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "site-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let text { try text.write(to: url.appending(path: SiteConfig.fileName), atomically: true, encoding: .utf8) }
        return url
    }

    @Test func noFileIsPlainCanteiro() throws {
        let config = try SiteConfig.load(site: site(nil))
        #expect(config == SiteConfig())
        #expect(config.inboxFolder == nil)
        #expect(config.publicURL(for: "x.webp") == nil)
        #expect(!config.isEpisodes("episodes-myshow"))
        #expect(config.extras.isEmpty)
    }

    @Test func readsTheFile() throws {
        let config = try SiteConfig.load(site: site(json))
        #expect(config.inboxFolder?.path == NSString(string: "~/Drafts/Blog").expandingTildeInPath)
        #expect(config.inboxFolder(site: URL(fileURLWithPath: "/Sites/a"))?.path == NSString(string: "~/Drafts/Blog").expandingTildeInPath)
        #expect(config.inbox?.app == "iA Writer")
        #expect(config.isEpisodes("episodes-myshow"))
        #expect(!config.isEpisodes("posts"))
        #expect(config.guid(show: "myshow", number: 4) == "myshow-ep4")
        #expect(config.audioFolder(show: "myshow") == "audio/myshow/")
        #expect(config.photoFolder(date: Date(timeIntervalSince1970: 1_791_000_000)) == "img/2026/")
        #expect(config.publicURL(for: "img/2026/x.webp") == "https://media.example.com/img/2026/x.webp")
        #expect(config.extras == [.highlight, .toc])
        #expect(config.audioField == "audioUrl", "field names fall back to the usual ones")
    }

    /// A relative inbox folder is inside the site, wherever the site is.
    @Test func aRelativeInboxIsInTheSite() throws {
        let config = try SiteConfig.load(site: site(#"{"inbox": {"folder": "inbox", "importInto": "posts"}}"#))
        #expect(config.inboxFolder(site: URL(fileURLWithPath: "/Sites/demo"))?.path == "/Sites/demo/inbox")
    }

    @Test func aBrokenFileSaysWhere() throws {
        let url = try site(#"{ "inbox": { "folder": "x" } }"#)
        #expect {
            try SiteConfig.load(site: url)
        } throws: { error in
            let text = error.localizedDescription
            return text.contains("canteiro.json") && text.contains("importInto")
        }
    }

    @MainActor @Test func extrasAreOffWithoutTheConfig() {
        let s = NSTextStorage(string: "==bright== and {{TOC}}\n")
        MarkdownStyler.style(s, mode: .rich)
        #expect(s.attributes(at: 2, effectiveRange: nil)[.backgroundColor] == nil, "== is just text on a plain site")
        MarkdownStyler.style(s, mode: .rich, syntax: [.highlight])
        #expect(s.attributes(at: 2, effectiveRange: nil)[.backgroundColor] != nil)
    }
}
