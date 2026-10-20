import AppKit
import CoreText

/// How the Rich view draws text: the app's own look, or the site's, from
/// canteiro.json's `rich` block. Fonts and colors are immutable, so it's
/// safe to share.
struct RichLook: Equatable, @unchecked Sendable {
    var body: NSFont = .systemFont(ofSize: 15)
    /// A family for headings; nil uses the system font.
    var headingFamily: String?
    var headingSizes: [CGFloat] = [26, 21, 18, 16, 15, 15]
    /// A line height in points, as CSS sets it. Nil keeps the app's spacing.
    var lineHeight: CGFloat?
    var width: CGFloat?
    var text: NSColor = .labelColor
    var headings: NSColor = .labelColor
    var links: NSColor = .linkColor
    var background: NSColor?
    /// What in the `rich` block couldn't be used, for the sidebar.
    var problems: [String] = []

    static let standard = RichLook()

    func headingFont(level: Int) -> NSFont {
        let size = headingSizes[min(level, headingSizes.count) - 1]
        if let headingFamily,
           let font = NSFontManager.shared.font(withFamily: headingFamily, traits: .boldFontMask, weight: 9, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: .bold)
    }
}

extension RichLook {
    /// The site's look. Its font files are loaded for this run of the app.
    /// Whatever can't be used stays as the app's and is listed in `problems`.
    init(_ rich: SiteConfig.Rich, site: URL) {
        var problems: [String] = []
        for path in rich.fonts ?? [] {
            let files = Self.files(path, site: site)
            if files.isEmpty { problems.append("no font file at \(path)") }
            files.forEach(Self.register)
        }
        func family(_ name: String?, size: CGFloat) -> NSFont? {
            guard let name else { return nil }
            if let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) { return font }
            problems.append("no font named \"\(name)\"")
            return nil
        }
        func color(_ pick: (SiteConfig.Rich.Colors) -> String?, _ fallback: NSColor) -> NSColor? {
            let light = rich.colors.flatMap(pick).flatMap { Self.hex($0, &problems) }
            let dark = rich.dark.flatMap(pick).flatMap { Self.hex($0, &problems) }
            guard light != nil || dark != nil else { return nil }
            return NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return (isDark ? dark : light) ?? fallback
            }
        }

        let size = CGFloat(rich.size ?? 15)
        self.init()
        body = family(rich.body, size: size) ?? .systemFont(ofSize: size)
        if family(rich.headings, size: size) != nil { headingFamily = rich.headings }
        headingSizes = rich.headingSizes.map { $0.map { CGFloat($0) * size } }
            ?? RichLook.standard.headingSizes.map { $0 * size / 15 }
        lineHeight = rich.lineHeight.map { CGFloat($0) * size }
        width = rich.width.map { CGFloat($0) }
        text = color(\.text, .labelColor) ?? .labelColor
        headings = color(\.headings, .labelColor) ?? .labelColor
        links = color(\.links, .linkColor) ?? .linkColor
        background = color(\.background, .clear)
        self.problems = problems.map { "\(SiteConfig.fileName): rich: \($0)" }
    }

    /// A path inside the site, with `*` matching in its file name.
    static func files(_ path: String, site: URL) -> [URL] {
        let url = site.appending(path: path)
        guard url.lastPathComponent.contains("*") else {
            return FileManager.default.fileExists(atPath: url.path) ? [url] : []
        }
        let folder = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { SiteConfig.matches($0, url.lastPathComponent) }.sorted().map { folder.appending(path: $0) }
    }

    /// Loads a font file (TTF, OTF, WOFF or WOFF2) for this process. Opening
    /// the same site again finds it already loaded, which is fine.
    private static func register(_ file: URL) {
        CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }

    static func hex(_ string: String, _ problems: inout [String]) -> NSColor? {
        var digits = string.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            problems.append("\"\(string)\" isn't a hex color")
            return nil
        }
        return NSColor(srgbRed: CGFloat(value >> 16 & 0xff) / 255, green: CGFloat(value >> 8 & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}
