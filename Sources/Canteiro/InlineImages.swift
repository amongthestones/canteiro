import AppKit
import ImageIO

/// Photos shown in the Rich view, fetched from their URLs once per run of
/// the app. Each is cut down to a screen's worth of pixels, so a folder of
/// camera originals doesn't fill memory.
@MainActor
final class InlineImages {
    static let shared = InlineImages()
    /// Posted with the URL string as the object when a photo arrives.
    static let loaded = Notification.Name("CanteiroInlineImageLoaded")

    private var images: [String: NSImage] = [:]
    private var tried: Set<String> = []

    func image(_ url: String) -> NSImage? { images[url] }

    /// The sizes of the photos in `urls` that have arrived. The rest start
    /// loading, and `loaded` says when each is ready.
    func sizes(_ urls: [String]) -> [String: NSSize] {
        var sizes: [String: NSSize] = [:]
        for url in urls {
            if let image = images[url] { sizes[url] = image.size } else { load(url) }
        }
        return sizes
    }

    private func load(_ string: String) {
        guard !tried.contains(string), let url = URL(string: string), ["http", "https"].contains(url.scheme) else { return }
        tried.insert(string)
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = await Task.detached(priority: .utility, operation: { Self.thumbnail(data) }).value else { return }
            images[string] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            NotificationCenter.default.post(name: Self.loaded, object: string)
        }
    }

    /// The photo at most 1600 pixels across, turned the way its EXIF says.
    nonisolated private static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A photo to draw above its `![](…)` line, at this size.
final class InlineImage: NSObject {
    let url: String
    let size: NSSize

    init(url: String, size: NSSize) {
        self.url = url
        self.size = size
    }
}

extension NSAttributedString.Key {
    static let inlineImage = NSAttributedString.Key("canteiroInlineImage")
}
