import AVFoundation
import Foundation
import Testing
@testable import Canteiro

/// Saves into a scratch copy of the CANTEIRO_TEST_SITE site, never the site
/// itself. Each test finds what it needs by shape (a collection with drafts,
/// the asides stream, a podcast collection from canteiro.json) and returns
/// early when the site has none.
@MainActor
@Suite struct SaveTests {
    nonisolated static let site = SiteTests.site
    nonisolated static var hasSite: Bool { SiteTests.hasSite }

    /// The site in a temp folder, sharing its node_modules. Build output,
    /// public files and git are left behind.
    private func scratchSite() throws -> URL {
        let fm = FileManager.default
        let copy = fm.temporaryDirectory.appending(path: "canteiro-test-\(UUID().uuidString)")
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        let skip: Set<String> = ["node_modules", ".git", "dist", ".astro", "public", ".netlify", ".wrangler", ".vercel"]
        for name in try fm.contentsOfDirectory(atPath: Self.site.path) where !skip.contains(name) {
            try fm.copyItem(at: Self.site.appending(path: name), to: copy.appending(path: name))
        }
        try fm.createSymbolicLink(at: copy.appending(path: "node_modules"), withDestinationURL: Self.site.appending(path: "node_modules"))
        return copy
    }

    private func open() async throws -> (SiteStore, URL) {
        let copy = try scratchSite()
        let store = SiteStore()
        await store.open(copy)
        _ = try #require(store.schema)
        return (store, copy)
    }

    private func collections(_ store: SiteStore) -> [SchemaItem] {
        store.schema?.items.filter { $0.kind == .collection } ?? []
    }

    private func hasDraft(_ item: SchemaItem) -> Bool {
        item.dataFields.contains { $0.key == "draft" && $0.type == "checkbox" }
    }

    @Test(.enabled(if: hasSite))
    func savingChangesOnlyTheEditedLine() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        let found = collections(store).lazy.compactMap { item -> (SchemaItem, Entry)? in
            guard self.hasDraft(item), let entry = store.entries[item.key]?.first(where: { $0.data["draft"]?.bool != nil }) else { return nil }
            return (item, entry)
        }.first
        guard let (item, entry) = found else { return }

        let flipped = !(entry.data["draft"]?.bool ?? false)
        var data = entry.data
        data["draft"] = .bool(flipped)
        store.save(item, id: entry.id, data: data, body: entry.body)

        let after = try String(contentsOf: entry.url, encoding: .utf8)
        let before = entry.raw.components(separatedBy: "\n")
        let now = after.components(separatedBy: "\n")
        #expect(before.count == now.count)
        let changed = zip(before, now).filter { $0 != $1 }
        #expect(changed.count == 1, "\(changed)")
        #expect(changed.first?.1 == "draft: \(flipped)")
        #expect(store.current(item, id: entry.id)?.data["draft"] == .bool(flipped))
    }

    @Test(.enabled(if: hasSite))
    func aChangeOnDiskIsNeverWrittenOver() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        let found = collections(store).lazy.compactMap { item -> (SchemaItem, Entry)? in
            guard item.bodyField != nil, let entry = store.entries[item.key]?.first else { return nil }
            return (item, entry)
        }.first
        guard let (item, entry) = found else { return }

        let elsewhere = entry.raw + "\nAdded in another editor.\n"
        try elsewhere.write(to: entry.url, atomically: true, encoding: .utf8)
        store.save(item, id: entry.id, data: entry.data, body: (entry.body ?? "") + "Typed in Canteiro.")

        #expect(store.conflicts.contains(entry.id))
        #expect(try String(contentsOf: entry.url, encoding: .utf8) == elsewhere)

        store.reread(item, id: entry.id)
        #expect(!store.conflicts.contains(entry.id))
        #expect(store.current(item, id: entry.id)?.raw == elsewhere)
    }

    @Test(.enabled(if: hasSite))
    func aNewAsideLooksLikeKeystatics() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        guard let item = store.streamItem, let textField = item.textField else { return }
        let languageField = item.dataFields.first { $0.type == "select" && $0.key.hasPrefix("lang") }
        let language = languageField?.options?.first?.value
        let before = store.entries[item.key]?.count ?? 0
        try store.createAside(text: "Autumn: the leaves are out: rain soon.", language: language)

        let asides = try #require(store.entries[item.key])
        #expect(asides.count == before + 1)
        let new = try #require(asides.first { $0.id == store.selectedEntry[item.key] })
        let lines = new.raw.split(separator: "\n").map(String.init)
        let keys = lines.filter { !$0.hasPrefix(" ") && !$0.hasPrefix("-") }.map { String($0.prefix { $0 != ":" }) }
        #expect(keys == item.dataFields.map(\.key).filter(keys.contains), "fields in the config's order")
        #expect(lines.contains("\(textField.key): \"Autumn: the leaves are out: rain soon.\""), "a colon gets quotes")
        if let date = item.dateField { #expect(new.data[date.key]?.date != nil) }
        if let languageField, let language { #expect(new.data[languageField.key] == .string(language)) }
    }

    @Test(.enabled(if: hasSite))
    func aDroppedEpisodeBecomesADraft() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        guard let item = collections(store).first(where: { store.isEpisodes($0) }) else { return }
        let config = store.config
        let show = URL(fileURLWithPath: item.folder).lastPathComponent
        let audio = "https://media.example.com/\(config.audioFolder(show: show))canteiro-test-001.mp3"

        try store.addEpisode(item, slug: "canteiro-test-001", number: 1, seconds: 768.4, audioURL: audio)
        let entry = try #require(store.entries[item.key]?.first { $0.slug == "canteiro-test-001" })
        let fields = Set(item.dataFields.map(\.key))
        if hasDraft(item) { #expect(entry.data["draft"] == .bool(true)) }
        if fields.contains(config.numberField) { #expect(entry.data[config.numberField] == .int(1)) }
        if fields.contains(config.guidField) { #expect(entry.data[config.guidField] == .string(config.guid(show: show, number: 1))) }
        if fields.contains(config.durationField) { #expect(entry.data[config.durationField] == .string("00:12:48")) }
        #expect(entry.data[config.audioField] == .string(audio))
    }

    @Test(.enabled(if: hasSite))
    func trashingAnEntryMovesTheNextOneUp() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        guard let item = collections(store).first(where: { (store.entries[$0.key]?.count ?? 0) >= 2 }) else { return }
        let list = try #require(store.entries[item.key])
        let (first, second) = (list[0], list[1])
        store.selectedEntry[item.key] = first.id

        let trashed = store.trash(item, ids: [first.id])
        defer { for url in trashed { try? FileManager.default.removeItem(at: url) } }
        #expect(trashed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(store.entries[item.key]?.count == list.count - 1)
        #expect(store.selectedEntry[item.key] == second.id)
    }

    /// In every collection named by a title: the file is the title as a
    /// slug, it starts as a draft, and each field gets the config's default.
    @Test(.enabled(if: hasSite))
    func aNewEntryStartsAsADraftWithTheConfigDefaults() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        for item in collections(store) where item.slugField != nil && !item.isStream && !store.isEpisodes(item) {
            try store.createEntry(item, title: "  Anna's Røde mic, in Évora ")
            let entry = try #require(store.entries[item.key]?.first { $0.id == store.selectedEntry[item.key] })
            #expect(entry.slug.hasSuffix("annas-rode-mic-in-evora"), "\(item.key)")
            #expect(entry.data[item.slugField!] == .string("Anna's Røde mic, in Évora"), "\(item.key)")
            if hasDraft(item) { #expect(entry.data["draft"] == .bool(true), "\(item.key)") }
            for field in item.dataFields where field.key != item.slugField && field.key != "draft" {
                guard let initial = SiteStore.initial(field) else { continue }
                if initial.date != nil {
                    #expect(entry.data[field.key]?.date != nil || entry.data[field.key]?.string != nil, "\(item.key).\(field.key)")
                } else {
                    #expect(entry.data[field.key] == initial, "\(item.key).\(field.key)")
                }
            }
            if item.bodyField != nil { #expect(entry.body == "", "\(item.key)") }
        }
    }

    /// A chosen image or file lands where Keystatic looks, the entry changes
    /// by that one line, and removing it takes the line out again.
    @Test(.enabled(if: hasSite))
    func aChosenFileSavesWhereKeystaticReadsIt() async throws {
        let (store, copy) = try await open()
        defer { try? FileManager.default.removeItem(at: copy) }
        let schema = try #require(store.schema)
        let found = schema.items.lazy.compactMap { item -> (SchemaItem, Entry, FieldSpec)? in
            guard let field = item.dataFields.first(where: \.isAsset) else { return nil }
            let entry = item.kind == .singleton ? store.singletons[item.key] : store.entries[item.key]?.first
            return entry.map { (item, $0, field) }
        }.first
        guard let (item, entry, field) = found else { return }

        let source = copy.appending(path: "chosen.\(field.type == "image" ? "png" : "txt")")
        try Data("not really a picture".utf8).write(to: source)
        let place = AssetPlace(site: copy, item: item, slug: entry.slug)
        let value = try place.store(source, field, path: [field.key])
        var data = entry.data
        data[field.key] = .string(value)
        store.save(item, id: entry.id, data: data, body: entry.body)

        let saved = try #require(store.current(item, id: entry.id))
        #expect(saved.raw.contains("\(field.key): \(value)\n"))
        #expect(FileManager.default.fileExists(atPath: try #require(place.url(for: value, field)).path))
        let changed = Set(saved.raw.components(separatedBy: "\n")).symmetricDifference(entry.raw.components(separatedBy: "\n"))
        #expect(changed.count <= 2, "\(changed)")

        data[field.key] = nil
        store.save(item, id: entry.id, data: data, body: entry.body)
        #expect(store.current(item, id: entry.id)?.raw.contains("\(field.key):") == false)
    }

    @Test func audioLengthReads() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "canteiro-say-\(UUID().uuidString).m4a")
        _ = try Subprocess.run("/usr/bin/say", ["-o", file.path, "--data-format=aac", "Good morning"], timeout: 30)
        let seconds = try await AVURLAsset(url: file).load(.duration).seconds
        #expect(seconds > 0.3 && seconds < 5)
    }
}
