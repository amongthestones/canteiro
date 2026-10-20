import Foundation

/// Renaming an entry, as Keystatic does it: the slug is the file's name, so
/// the file moves, with its folder of images and files, and paths in the
/// entry that name the old slug follow it.
enum Renamer {
    struct Plan: Equatable {
        /// Files and folders to move, from the site's root.
        var moves: [Move]
        /// Text to swap in the entry's file: the old asset paths for new.
        var replacements: [Replacement]

        struct Move: Equatable { let from: String; let to: String }
        struct Replacement: Equatable { let old: String; let new: String }
    }

    /// The new slug from what was typed. A nested slug (`work/chapter`)
    /// keeps its folder; only its last part is renamed.
    static func slug(_ typed: String, replacing old: String) -> String {
        let last = typed.split(separator: "/").last.map(String.init) ?? typed
        let folder = old.split(separator: "/").dropLast().joined(separator: "/")
        return (folder.isEmpty ? "" : folder + "/") + Slug.make(last)
    }

    static func plan(site: URL, item: SchemaItem, from old: String, to new: String) -> Plan {
        let before = AssetPlace(site: site, item: item, slug: old)
        let after = AssetPlace(site: site, item: item, slug: new)
        var moves: [Plan.Move] = []
        if let star = item.path.firstIndex(of: "*"), !AssetPlace.trimmed(String(item.path[star...].drop { $0 == "*" })).isEmpty {
            // posts/*/index: the entry is a folder, and everything in it goes.
            let head = String(item.path[..<star])
            moves.append(.init(from: head + old, to: head + new))
        } else {
            moves.append(.init(from: before.base + "." + item.fileExtension, to: after.base + "." + item.fileExtension))
            // Files from fields without a directory sit in a folder by the entry.
            moves.append(.init(from: before.base, to: after.base))
        }
        var replacements: [Plan.Replacement] = []
        for spec in assetSpecs(item.dataFields) {
            if spec.directory != nil {
                let move = Plan.Move(from: before.folder(spec), to: after.folder(spec))
                if !moves.contains(move) { moves.append(move) }
            }
            let replacement = Plan.Replacement(old: before.prefix(spec), new: after.prefix(spec))
            if !replacement.old.isEmpty, !replacements.contains(replacement) { replacements.append(replacement) }
        }
        return Plan(moves: moves, replacements: replacements)
    }

    /// Every image and file field, inside objects and lists too.
    static func assetSpecs(_ fields: [FieldSpec]) -> [FieldSpec] {
        fields.flatMap { field -> [FieldSpec] in
            if field.isAsset { return [field] }
            return assetSpecs((field.fields ?? []) + (field.element.map { [$0] } ?? []))
        }
    }

    /// Moves what exists of the plan and fixes the paths in the entry's
    /// file, at `entry` once moved. Stops before touching anything if a
    /// destination is taken.
    static func apply(_ plan: Plan, site: URL, entry: String) throws {
        let fm = FileManager.default
        let moves = plan.moves.filter { fm.fileExists(atPath: site.appending(path: $0.from).path) }
        if let taken = moves.first(where: { fm.fileExists(atPath: site.appending(path: $0.to).path) }) {
            throw Failure.taken(taken.to)
        }
        for move in moves {
            let to = site.appending(path: move.to)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: site.appending(path: move.from), to: to)
        }
        guard !plan.replacements.isEmpty else { return }
        let file = site.appending(path: entry)
        var text = try String(contentsOf: file, encoding: .utf8)
        for replacement in plan.replacements { text = text.replacingOccurrences(of: replacement.old, with: replacement.new) }
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Sends the old address to the new one in a `_redirects` file
    /// (Cloudflare Pages and Netlify read the same format). Rules that sent
    /// somewhere to the old address now go straight to the new one.
    static func redirect(_ file: URL, from old: String, to new: String) throws {
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n").map { line -> String in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, !line.hasPrefix("#"), parts[1] == old else { return line }
            return ([String(parts[0]), new] + parts.dropFirst(2).map(String.init)).joined(separator: "  ")
        }
        while lines.last == "" { lines.removeLast() }
        let header = "# Renamed in Canteiro"
        if !lines.contains(header) { lines += ["", header] }
        lines.append("\(old)  \(new)  301")
        text = lines.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    enum Failure: LocalizedError {
        case taken(String)
        case sameName
        var errorDescription: String? {
            switch self {
            case .taken(let path): return "\(path) already exists."
            case .sameName: return "Another entry already has that address."
            }
        }
    }
}
