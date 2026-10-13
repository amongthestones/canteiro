import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Where an entry's image and file fields keep their files in the repo,
/// worked out as Keystatic does it, so either one can edit the entry:
///
/// - The file is named after the field (`photo.jpg`), with its folders for
///   a field inside a group (`hero/photo.jpg`).
/// - With a `directory`, it goes there, in a folder named after the entry's
///   slug for a collection. Without one, it goes in a folder next to the
///   entry, named like it (`src/content/posts/my-post/photo.jpg`).
/// - The entry stores the file name after `publicPath` and the slug
///   (`/images/posts/my-post/photo.jpg`), or the bare file name without a
///   `publicPath`.
struct AssetPlace: Sendable {
    let site: URL
    let item: SchemaItem
    /// The entry's slug in a collection; nil for a singleton.
    let slug: String?

    init(site: URL, item: SchemaItem, slug: String?) {
        self.site = site
        self.item = item
        self.slug = item.kind == .collection ? slug : nil
    }

    /// The entry's own path without an extension: Keystatic's home for
    /// files when a field has no directory.
    var base: String {
        guard let slug, let star = item.path.firstIndex(of: "*") else { return Self.trimmed(item.path) }
        let after = Self.trimmed(String(item.path[star...].drop { $0 == "*" }))
        return item.path[..<star] + slug + (after.isEmpty ? "" : "/" + after)
    }

    /// The folder the field's files go in, from the site's root.
    func folder(_ spec: FieldSpec) -> String {
        guard let directory = spec.directory else { return base }
        return Self.trimmed(directory) + (slug.map { "/" + $0 } ?? "")
    }

    /// What comes before the file name in the entry.
    func prefix(_ spec: FieldSpec) -> String {
        guard let publicPath = spec.publicPath else { return "" }
        return publicPath.replacing(/\/*$/, with: "") + "/" + (slug.map { $0 + "/" } ?? "")
    }

    /// The file a value names, or nil when it isn't one of this field's.
    func url(for value: String, _ spec: FieldSpec) -> URL? {
        let prefix = prefix(spec)
        guard !value.isEmpty, value.hasPrefix(prefix), value.count > prefix.count else { return nil }
        return site.appending(path: folder(spec)).appending(path: String(value.dropFirst(prefix.count)))
    }

    /// The value for a file of this field, named after the field's path.
    func value(for source: URL, _ spec: FieldSpec, path: [String]) -> String {
        let ext = source.pathExtension
        return prefix(spec) + path.joined(separator: "/") + (ext.isEmpty ? "" : "." + ext)
    }

    /// Copies a file in as the field's file and returns the field's new
    /// value. A file already there by that name is replaced.
    func store(_ source: URL, _ spec: FieldSpec, path: [String]) throws -> String {
        let value = value(for: source, spec, path: path)
        guard let target = url(for: value, spec) else { throw CocoaError(.fileWriteInvalidFileName) }
        guard source.standardizedFileURL != target.standardizedFileURL else { return value }
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: source, to: target)
        return value
    }

    /// Moves a field's file to the Trash and returns where it went. In a
    /// collection, the entry's folders it leaves empty go too.
    @discardableResult
    func trash(_ file: URL, _ spec: FieldSpec) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }
        var moved: NSURL?
        try fm.trashItem(at: file, resultingItemURL: &moved)
        guard slug != nil else { return moved as URL? }
        let stop = site.appending(path: folder(spec)).standardizedFileURL.path
        var dir = file.deletingLastPathComponent().standardizedFileURL
        while dir.path.hasPrefix(stop), (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? fm.removeItem(at: dir)
            if dir.path == stop { break }
            dir = dir.deletingLastPathComponent()
        }
        return moved as URL?
    }

    /// Every file the entry's image and file fields name, with its field,
    /// in groups too. Lists are skipped: Canteiro doesn't place files in them.
    func files(_ fields: [FieldSpec], in data: FieldValue) -> [(URL, FieldSpec)] {
        fields.flatMap { field -> [(URL, FieldSpec)] in
            if field.isAsset, let value = data[field.key]?.string, let url = url(for: value, field) { return [(url, field)] }
            if field.type == "object", let inner = data[field.key] { return files(field.fields ?? [], in: inner) }
            return []
        }
    }

    /// Keystatic's fixPath: no leading ./ or /, no trailing /.
    static func trimmed(_ path: String) -> String {
        path.replacing(/^\.?\/+/, with: "").replacing(/\/*$/, with: "")
    }
}

/// An image or file field: the file's name, a preview for an image, and
/// buttons to choose or remove it. A file dropped on it is taken too.
struct AssetField: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.assetPlace) private var place
    @Environment(\.fieldPath) private var path
    @Environment(\.inSettingsForm) private var inSettingsForm
    let spec: FieldSpec
    @Binding var value: FieldValue
    @State private var preview: CGImage?
    /// Bumped when a file is replaced under the same name, to reload it.
    @State private var version = 0
    @State private var dropping = false

    private var isImage: Bool { spec.type == "image" }

    var body: some View {
        if let place, let path, !path.isEmpty {
            editor(place, path)
        } else {
            // In a list, where Keystatic names files by each item's slug.
            name.textSelection(.enabled)
        }
    }

    private var name: some View {
        Text(value.isEmpty ? Placeholder.text(for: spec) : value.string ?? "")
            .font(.callout.monospaced())
            .foregroundStyle(value.isEmpty ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func editor(_ place: AssetPlace, _ path: [String]) -> some View {
        let file = value.string.flatMap { place.url(for: $0, spec) }
        let missing = file.map { !FileManager.default.fileExists(atPath: $0.path) } ?? !value.isEmpty
        return HStack(alignment: .center, spacing: 12) {
            if isImage, let preview, !missing {
                Image(decorative: preview, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 72, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            }
            VStack(alignment: inSettingsForm ? .trailing : .leading, spacing: 3) {
                name.textSelection(.enabled)
                if missing {
                    Label("Not found in the site", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(value.isEmpty ? "Choose…" : "Replace…") { choose(place, path) }
                    if !value.isEmpty {
                        Button("Remove") { remove(place, file) }
                    }
                    if let file, !missing {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(4)
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            take(url, place, path)
            return true
        } isTargeted: { dropping = $0 }
        .task(id: "\(file?.path ?? "")#\(version)") {
            guard isImage, let file else { preview = nil; return }
            preview = await Task.detached { Self.thumbnail(file) }.value
        }
    }

    private func choose(_ place: AssetPlace, _ path: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if isImage { panel.allowedContentTypes = [.image] }
        panel.message = "Choose \(isImage ? "an image" : "a file") for \(spec.title)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            take(url, place, path)
        }
    }

    /// Copies the file into the site and points the field at it. A file
    /// the field named before, by another name, goes to the Trash.
    private func take(_ source: URL, _ place: AssetPlace, _ path: [String]) {
        if isImage, UTType(filenameExtension: source.pathExtension)?.conforms(to: .image) != true {
            store.lastError = "\(source.lastPathComponent) isn't an image."
            return
        }
        let old = value.string.flatMap { place.url(for: $0, spec) }
        do {
            let new = try place.store(source, spec, path: path)
            if let old, old.standardizedFileURL != place.url(for: new, spec)?.standardizedFileURL {
                try place.trash(old, spec)
            }
            value = .string(new)
            version += 1
            store.refreshChanges()
        } catch {
            store.lastError = "\(source.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func remove(_ place: AssetPlace, _ file: URL?) {
        do {
            if let file { try place.trash(file, spec) }
            value = .null
            store.refreshChanges()
        } catch {
            store.lastError = "\(file?.lastPathComponent ?? spec.title): \(error.localizedDescription)"
        }
    }

    nonisolated private static func thumbnail(_ file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension EnvironmentValues {
    /// Where the open entry's image and file fields keep their files.
    @Entry var assetPlace: AssetPlace?
    /// The keys from the entry down to the field being drawn, which name its
    /// file. Nil inside a list or a conditional, where files stay read-only.
    @Entry var fieldPath: [String]? = []
}

extension Binding where Value == FieldValue {
    /// A field's value in its group. An emptied image or file field drops
    /// out of the entry, as in Keystatic, which reads `null` there as an error.
    func field(_ spec: FieldSpec) -> Binding<FieldValue> {
        guard spec.isAsset else { return child(spec.key) }
        return Binding(
            get: { wrappedValue[spec.key] ?? .null },
            set: { wrappedValue[spec.key] = $0 == .null ? nil : $0 }
        )
    }
}
