import AVFoundation
import Foundation
import Testing
@testable import Canteiro

/// Saves into a scratch copy of the real site, never the site itself.
@MainActor
@Suite struct SaveTests {
    nonisolated static let site = SiteTests.site

    /// The site's config and content in a temp folder, sharing its node_modules.
    private func scratchSite() throws -> URL {
        let fm = FileManager.default
        let copy = fm.temporaryDirectory.appending(path: "canteiro-test-\(UUID().uuidString)")
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        for name in ["keystatic.config.ts", "package.json", "src", SiteConfig.fileName]
            where fm.fileExists(atPath: Self.site.appending(path: name).path) {
            try fm.copyItem(at: Self.site.appending(path: name), to: copy.appending(path: name))
        }
        try fm.createSymbolicLink(at: copy.appending(path: "node_modules"), withDestinationURL: Self.site.appending(path: "node_modules"))
        return copy
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func savingChangesOnlyTheEditedLine() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        let entry = try #require(store.entries["posts"]?.first { $0.data["draft"]?.bool == true })

        var data = entry.data
        data["draft"] = .bool(false)
        store.save(item, id: entry.id, data: data, body: entry.body)

        let after = try String(contentsOf: entry.url, encoding: .utf8)
        let before = entry.raw.components(separatedBy: "\n")
        let now = after.components(separatedBy: "\n")
        #expect(before.count == now.count)
        let changed = zip(before, now).filter { $0 != $1 }
        #expect(changed.count == 1, "\(changed)")
        #expect(changed.first?.1 == "draft: false")
        #expect(store.current(item, id: entry.id)?.data["draft"] == .bool(false))
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aChangeOnDiskIsNeverWrittenOver() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        let entry = try #require(store.entries["posts"]?.first)

        let elsewhere = entry.raw + "\nAdded in iA Writer.\n"
        try elsewhere.write(to: entry.url, atomically: true, encoding: .utf8)
        store.save(item, id: entry.id, data: entry.data, body: (entry.body ?? "") + "Typed in Canteiro.")

        #expect(store.conflicts.contains(entry.id))
        #expect(try String(contentsOf: entry.url, encoding: .utf8) == elsewhere)

        store.reread(item, id: entry.id)
        #expect(!store.conflicts.contains(entry.id))
        #expect(store.current(item, id: entry.id)?.raw == elsewhere)
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aNewAsideLooksLikeKeystatics() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let before = store.entries["asides"]?.count ?? 0
        try store.createAside(text: "Autumn: the chestnuts are out: magosto soon.", language: "en")

        let asides = try #require(store.entries["asides"])
        #expect(asides.count == before + 1)
        let new = try #require(asides.first { $0.id == store.selectedEntry["asides"] })
        let lines = new.raw.split(separator: "\n").map(String.init)
        #expect(lines.map { String($0.prefix { $0 != ":" }) } == ["name", "draft", "text", "date", "language"])
        #expect(lines[0] == "name: \(new.slug)")
        #expect(lines[1] == "draft: false")
        #expect(lines[2] == "text: \"Autumn: the chestnuts are out: magosto soon.\"")
        #expect(lines[3].range(of: #"^date: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000Z$"#, options: .regularExpression) != nil)
        #expect(lines[4] == "language: en")
        #expect(new.data["date"]?.date != nil)
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aDroppedEpisodeBecomesADraft() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("episodes-corrixeme"))
        #expect(store.isEpisodes(item))

        try store.addEpisode(item, slug: "corrixeme-001", number: 1, seconds: 768.4,
                             audioURL: "https://media.amongthestones.com/podcasts/corrixeme/corrixeme-001.mp3")
        let entry = try #require(store.entries["episodes-corrixeme"]?.first { $0.slug == "corrixeme-001" })
        #expect(entry.id == "src/content/episodes/corrixeme/corrixeme-001.md")
        #expect(entry.data["title"] == .string("Episode 1"))
        #expect(entry.data["draft"] == .bool(true))
        #expect(entry.data["guid"] == .string("corrixeme-1"))
        #expect(entry.data["duration"] == .string("00:12:48"))
        #expect(entry.data["episodeType"] == .string("full"))
        #expect(entry.data["fileSize"] == nil, "the README says leave it empty")
        #expect(entry.data["audioUrl"]?.string?.hasPrefix("https://media.amongthestones.com/") == true)
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func trashingAnEntryMovesTheNextOneUp() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        let list = try #require(store.entries["posts"])
        let (first, second) = (list[0], list[1])
        store.selectedEntry["posts"] = first.id

        let trashed = store.trash(item, ids: [first.id])
        defer { for url in trashed { try? FileManager.default.removeItem(at: url) } }
        #expect(trashed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(store.entries["posts"]?.count == list.count - 1)
        #expect(store.selectedEntry["posts"] == second.id)
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aNewPostStartsAsADraftWithTheConfigDefaults() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        let item = try #require(store.schema?.item("posts"))
        try store.createEntry(item, title: "  Jimmy's Røde mic, in Monforte ")

        let entry = try #require(store.entries["posts"]?.first { $0.id == store.selectedEntry["posts"] })
        #expect(entry.slug == "jimmys-rode-mic-in-monforte")
        #expect(entry.data["title"] == .string("Jimmy's Røde mic, in Monforte"))
        #expect(entry.data["draft"] == .bool(true))
        #expect(entry.data["categories"] == .array([.string("posts")]))
        #expect(entry.data["language"] == .string("en"))
        #expect(entry.data["date"]?.date != nil)
        #expect(entry.body == "")
    }

    @Test(.enabled(if: SiteStore.isSite(site)))
    func aNewWorkAndChapterGetTheirDefaults() async throws {
        let copy = try scratchSite()
        defer { try? FileManager.default.removeItem(at: copy) }
        let store = SiteStore()
        await store.open(copy)
        try store.createEntry(try #require(store.schema?.item("works")), title: "The Long Field")
        let work = try #require(store.entries["works"]?.first { $0.id == store.selectedEntry["works"] })
        #expect(work.data["series"]?["discriminant"] == .string("stories"))
        #expect(work.data["series"]?["value"] == .string("short"))

        try store.createEntry(try #require(store.schema?.item("fiction")), title: "The Long Field")
        let part = try #require(store.entries["fiction"]?.first { $0.id == store.selectedEntry["fiction"] })
        #expect(part.data["part"] == .int(1))
        #expect(part.data["draft"] == .bool(true))
        #expect(part.data["date"]?.string?.count == 10)
    }

    @Test func audioLengthReads() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "canteiro-say-\(UUID().uuidString).m4a")
        _ = try Subprocess.run("/usr/bin/say", ["-o", file.path, "--data-format=aac", "Bo día"], timeout: 30)
        let seconds = try await AVURLAsset(url: file).load(.duration).seconds
        #expect(seconds > 0.3 && seconds < 5)
    }
}
