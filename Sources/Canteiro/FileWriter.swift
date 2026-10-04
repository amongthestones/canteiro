import Foundation

/// Writes an entry back to its file. A field that didn't change keeps its
/// original text, quoting and comments included, so a save's git diff shows
/// only what was edited. Changed and new fields are written the way Keystatic
/// writes them. The body is written exactly as typed.
enum FileWriter {
    /// The file's new text, or nil when nothing changed.
    static func text(for entry: Entry, data: FieldValue, body: String?, format: Format) -> String? {
        guard data != entry.data || body != entry.body else { return nil }
        if format.data == "json" && format.contentField == nil {
            return JSONEmitter.document(data)
        }
        if format.contentField != nil {
            let original = YAMLReader.splitFrontmatter(entry.raw)
            let yaml = data == entry.data ? original.yaml : YAMLSplicer.yaml(original: original.yaml, old: entry.data, new: data)
            return "---\n" + yaml + "\n---\n" + (body ?? "")
        }
        return YAMLSplicer.yaml(original: entry.raw, old: entry.data, new: data)
    }
}

/// Rebuilds YAML from the original text, one top-level key at a time.
enum YAMLSplicer {
    static func yaml(original: String, old: FieldValue, new: FieldValue) -> String {
        let endsWithNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }

        // Lines before the first key (comments, blank lines) stay on top.
        // Each key owns its line and every indented or blank line after it.
        var preamble: [String] = []
        var chunks: [String: [String]] = [:]
        var current: String?
        for line in lines {
            if let key = topLevelKey(line) {
                current = key
                chunks[key] = [line]
            } else if let current {
                chunks[current]?.append(line)
            } else {
                preamble.append(line)
            }
        }

        var out = preamble
        guard case .object(let pairs) = new else { return original }
        for pair in pairs {
            if let chunk = chunks[pair.key], old[pair.key] == pair.value {
                out += chunk
            } else {
                // A replaced key keeps the blank lines that followed it.
                let spacing = chunks[pair.key]?.reversed().prefix(while: \.isEmpty).count ?? 0
                out += YAMLEmitter.lines(key: pair.key, value: pair.value, indent: 0)
                out += Array(repeating: "", count: spacing)
            }
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
    }

    /// The key of a line that starts a top-level mapping entry.
    static func topLevelKey(_ line: String) -> String? {
        guard let first = line.first, first != " ", first != "\t", first != "#", first != "-" else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let after = line.index(after: colon)
        guard after == line.endIndex || line[after] == " " else { return nil }
        var key = String(line[..<colon])
        if key.count >= 2, let q = key.first, q == "\"" || q == "'", key.last == q {
            key = String(key.dropFirst().dropLast())
        }
        return key
    }
}

/// YAML in Keystatic's style: block lists and maps, two-space indents, plain
/// strings where they read back the same, quoted ones elsewhere.
enum YAMLEmitter {
    static func lines(key: String, value: FieldValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let name = plainKey(key)
        switch value {
        case .object(let pairs) where !pairs.isEmpty:
            return ["\(pad)\(name):"] + pairs.flatMap { lines(key: $0.key, value: $0.value, indent: indent + 2) }
        case .array(let items) where !items.isEmpty:
            return ["\(pad)\(name):"] + items.flatMap { item(value: $0, indent: indent + 2) }
        case .string(let s) where s.contains("\n"):
            return ["\(pad)\(name): \(blockIndicator(s))"] + blockLines(s, indent: indent + 2)
        default:
            return ["\(pad)\(name): \(scalar(value))"]
        }
    }

    /// A list item: `- value`, or `- key: value` with the rest of the map
    /// lined up under it.
    static func item(value: FieldValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch value {
        case .object(let pairs) where !pairs.isEmpty:
            var out = pairs.flatMap { lines(key: $0.key, value: $0.value, indent: indent + 2) }
            out[0] = pad + "- " + String(out[0].dropFirst(indent + 2))
            return out
        case .array(let items) where !items.isEmpty:
            var out = items.flatMap { item(value: $0, indent: indent + 2) }
            out[0] = pad + "- " + String(out[0].dropFirst(indent + 2))
            return out
        case .string(let s) where s.contains("\n"):
            return ["\(pad)- \(blockIndicator(s))"] + blockLines(s, indent: indent + 2)
        default:
            return ["\(pad)- \(scalar(value))"]
        }
    }

    static func scalar(_ value: FieldValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .date(_, let raw): return raw
        case .string(let s): return string(s)
        case .array: return "[]"
        case .object: return "{}"
        }
    }

    /// Plain when it can't be mistaken for anything else, double-quoted otherwise.
    static func string(_ s: String) -> String {
        needsQuotes(s) ? JSONEmitter.quoted(s) : s
    }

    static func needsQuotes(_ s: String) -> Bool {
        if s.isEmpty || s != s.trimmingCharacters(in: .whitespaces) { return true }
        if let first = s.unicodeScalars.first, "-?:,[]{}#&*!|>'\"%@`".unicodeScalars.contains(first) { return true }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        if s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return true }
        let lower = s.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n"].contains(lower) { return true }
        // Anything that reads back as a number or a date.
        if Double(s) != nil || Int(s) != nil || s.hasPrefix("0x") || s.hasPrefix("0o") { return true }
        // A YAML date: 2026-10-04 alone, or with a time after a T or a space.
        // 2026-10-04-1032 (an aside's name) is just a string.
        if s.range(of: #"^\d{4}-\d{1,2}-\d{1,2}([Tt]|\s|$)"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func blockIndicator(_ s: String) -> String {
        s.hasSuffix("\n") ? "|" : "|-"
    }

    private static func blockLines(_ s: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        var body = s
        if body.hasSuffix("\n") { body.removeLast() }
        return body.components(separatedBy: "\n").map { $0.isEmpty ? "" : pad + $0 }
    }

    private static func plainKey(_ key: String) -> String {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil ? key : JSONEmitter.quoted(key)
    }
}

/// JSON the way Keystatic writes it: JSON.stringify(value, null, 2) and a
/// newline, keys in order.
enum JSONEmitter {
    static func document(_ value: FieldValue) -> String {
        render(value, indent: 0) + "\n"
    }

    static func render(_ value: FieldValue, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            let body = pairs.map { "\(pad)\(quoted($0.key)): \(render($0.value, indent: indent + 2))" }
            return "{\n" + body.joined(separator: ",\n") + "\n\(close)}"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let body = items.map { pad + render($0, indent: indent + 2) }
            return "[\n" + body.joined(separator: ",\n") + "\n\(close)]"
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return quoted(s)
        case .date(_, let raw): return quoted(raw)
        }
    }

    /// A JSON string literal, escaped as JSON.stringify does.
    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
