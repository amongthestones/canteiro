import Foundation
import Yams

/// A value read from a frontmatter or data file. Objects keep their keys in
/// file order, and keys the schema doesn't know stay in place, so a save can
/// write the file back without dropping or shuffling anything.
indirect enum FieldValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    /// A YAML timestamp. `raw` is the text as written (2026-09-28 or
    /// 2026-09-28T23:10:00.000Z), so an untouched date saves unchanged.
    case date(Date, raw: String)
    case array([FieldValue])
    case object([FieldPair])
}

struct FieldPair: Sendable, Equatable {
    var key: String
    var value: FieldValue
}

extension FieldValue {
    subscript(key: String) -> FieldValue? {
        get {
            guard case .object(let pairs) = self else { return nil }
            return pairs.first { $0.key == key }?.value
        }
        set {
            var pairs: [FieldPair] = []
            if case .object(let existing) = self { pairs = existing }
            if let index = pairs.firstIndex(where: { $0.key == key }) {
                if let newValue { pairs[index].value = newValue } else { pairs.remove(at: index) }
            } else if let newValue {
                pairs.append(FieldPair(key: key, value: newValue))
            }
            self = .object(pairs)
        }
    }

    var isEmpty: Bool {
        switch self {
        case .null: return true
        case .string(let s): return s.isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return false
        }
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(_, let raw): return raw
        default: return nil
        }
    }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var array: [FieldValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// A date from a timestamp, or from a quoted string that looks like one
    /// (much of the imported WordPress frontmatter quotes its dates).
    var date: Date? {
        switch self {
        case .date(let d, _): return d
        case .string(let s): return FieldValue.parseDate(s)
        default: return nil
        }
    }

    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }
        // No zone: local time, which is what the old WordPress dates mean.
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            plain.dateFormat = format
            if let d = plain.date(from: text) { return d }
        }
        return nil
    }
}

/// Reads YAML (and JSON, which is YAML) into `FieldValue`, keeping order.
enum YAMLReader {
    static func parse(_ text: String) throws -> FieldValue {
        guard let node = try Yams.compose(yaml: text) else { return .object([]) }
        return value(node)
    }

    static func value(_ node: Node) -> FieldValue {
        switch node {
        case .scalar(let scalar):
            switch Tag.Name(rawValue: node.tag.rawValue) {
            case .null:
                return .null
            case .bool:
                return node.bool.map(FieldValue.bool) ?? .string(scalar.string)
            case .int:
                return node.int.map(FieldValue.int) ?? .string(scalar.string)
            case .float:
                return node.float.map(FieldValue.double) ?? .string(scalar.string)
            case .timestamp:
                if let date = node.timestamp { return .date(date, raw: scalar.string) }
                return .string(scalar.string)
            default:
                return .string(scalar.string)
            }
        case .mapping(let mapping):
            return .object(mapping.map { FieldPair(key: $0.key.string ?? "", value: value($0.value)) })
        case .sequence(let sequence):
            return .array(sequence.map(value))
        default:
            return .null
        }
    }

    /// Splits `---` frontmatter from the body. The body keeps its text
    /// exactly, leading blank line included.
    static func splitFrontmatter(_ text: String) -> (yaml: String, body: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ("", text) }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ("", text)
        }
        let yaml = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (yaml, body)
    }
}
