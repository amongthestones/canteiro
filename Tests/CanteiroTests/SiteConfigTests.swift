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
        MarkdownStyler.style(s, mode: .read)
        #expect(s.attributes(at: 2, effectiveRange: nil)[.backgroundColor] == nil, "== is just text on a plain site")
        MarkdownStyler.style(s, mode: .read, syntax: [.highlight])
        #expect(s.attributes(at: 2, effectiveRange: nil)[.backgroundColor] != nil)
    }
    @MainActor @Test func readTakesTheSitesLook() throws {
        let url = try site(#"""
        {"read": {"body": "Helvetica", "size": 18, "lineHeight": 1.5, "headingSizes": [2, 1.5],
                  "colors": {"text": "#222", "links": "#111"}, "fonts": ["fonts/*.woff2"]}}
        """#)
        let look = ReadLook(try SiteConfig.load(site: url).read!, site: url)
        #expect(look.body.familyName == "Helvetica" && look.body.pointSize == 18)
        #expect(look.lineHeight == 27)
        #expect(look.headingFont(level: 2).pointSize == 27)
        #expect(look.problems == ["canteiro.json: read: no font file at fonts/*.woff2"])

        let s = NSTextStorage(string: "## Head\n\nBody with a [link](https://x.y).\n")
        MarkdownStyler.style(s, mode: .read, look: look)
        let body = s.attributes(at: (s.string as NSString).range(of: "Body").location, effectiveRange: nil)
        #expect((body[.font] as? NSFont)?.familyName == "Helvetica")
        #expect((body[.paragraphStyle] as? NSParagraphStyle)?.minimumLineHeight == 27)
        var red: CGFloat = 0
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            red = (body[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.redComponent ?? 0
        }
        #expect(abs(red - 0x22 / 255) < 0.001)
        MarkdownStyler.style(s, mode: .markdown, look: look)
        #expect((s.attributes(at: 9, effectiveRange: nil)[.font] as? NSFont)?.isFixedPitch == true, "Markdown keeps its own look")
    }

    @Test func readListsWhatItCantUse() throws {
        let url = try site(#"{"read": {"body": "No Such Font", "colors": {"text": "red"}}}"#)
        let look = ReadLook(try SiteConfig.load(site: url).read!, site: url)
        #expect(look.body.pointSize == 15)
        #expect(look.problems.count == 2)
    }
}
