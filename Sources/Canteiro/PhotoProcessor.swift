import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes a photo ready for R2, by the site README's rules: 1400px wide (never
/// wider than the original), WebP at quality 75, no metadata, which also drops
/// the GPS location. ImageIO reads and resizes (HEIC too, turned upright);
/// cwebp encodes, since ImageIO can't write WebP.
enum PhotoProcessor {
    enum Failure: LocalizedError {
        case unreadable
        case noEncoder
        case encoder(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file isn't a photo Canteiro can read."
            case .noEncoder: return "WebP needs cwebp: brew install webp"
            case .encoder(let detail): return "cwebp failed: \(detail)"
            }
        }
    }

    struct Result: Sendable {
        let file: URL
        let width: Int
        let height: Int
        let bytesBefore: Int
        let bytesAfter: Int
    }

    static let width = 1400
    static let quality = 75

    static func process(_ source: URL) throws -> Result {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              var w = props[kCGImagePropertyPixelWidth] as? Int,
              var h = props[kCGImagePropertyPixelHeight] as? Int else { throw Failure.unreadable }
        // Orientations 5 to 8 are turned a quarter: the width is the height.
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&w, &h) }
        let targetWidth = min(width, w)
        let longest = max(targetWidth, Int((Double(h) * Double(targetWidth) / Double(w)).rounded()))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let resized = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else { throw Failure.unreadable }

        // A metadata-free PNG for cwebp to read.
        let work = FileManager.default.temporaryDirectory.appending(path: "canteiro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let png = work.appending(path: "photo.png")
        guard let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failure.unreadable }
        CGImageDestinationAddImage(dest, resized, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.unreadable }

        guard let cwebp = cwebpPath else {
            throw Failure.noEncoder
        }
        let out = work.appending(path: "photo.webp")
        let run = try Subprocess.run(cwebp, ["-quiet", "-q", String(quality), "-metadata", "none", png.path, "-o", out.path], timeout: 60)
        guard run.status == 0 else { throw Failure.encoder(run.stderrString) }

        let before = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let after = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Result(file: out, width: resized.width, height: resized.height, bytesBefore: before, bytesAfter: after)
    }

    /// Homebrew's cwebp, on Apple silicon or Intel.
    nonisolated static var cwebpPath: String? {
        ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first(where: FileManager.default.isExecutableFile)
    }

    /// The photo's name for the web in the site's photo folder:
    /// uploads/2026/10/cafe-a-noite.webp.
    static func key(for source: URL, in folder: String) -> String {
        folder + Slug.make(source.deletingPathExtension().lastPathComponent) + ".webp"
    }
}

/// File names for the web: lowercase ASCII, words joined by hyphens.
enum Slug {
    static func make(_ text: String) -> String {
        // Latin-ASCII spells out what stripping accents can't: ø as o, ß as ss.
        let ascii = text.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? text
        // "Anna's" is annas, as Keystatic makes it, not anna-s.
        let words = ascii.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "").split { !$0.isLetter && !$0.isNumber }
        let slug = words.joined(separator: "-").filter { $0.isASCII }
        return slug.isEmpty ? "file" : slug
    }
}
