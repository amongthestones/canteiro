import Foundation
import ImageIO
import Testing
@testable import Canteiro

@Suite struct PhotoTests {
    /// A big JPEG with a GPS location, made on the fly.
    private func photo(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "canteiro-photo-\(UUID().uuidString).jpg")
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for i in 0..<40 {
            ctx.setFillColor(red: CGFloat(i % 7) / 7, green: CGFloat(i % 5) / 5, blue: CGFloat(i % 3) / 3, alpha: 1)
            ctx.fill(CGRect(x: i * width / 40, y: 0, width: width / 40 + 1, height: height))
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 42.52, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 7.51, kCGImagePropertyGPSLongitudeRef: "W"]
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return url
    }

    @Test func resizesToWebPWithoutLocation() throws {
        let source = try photo(width: 4032, height: 3024)
        let result = try PhotoProcessor.process(source)
        #expect(result.file.pathExtension == "webp")
        #expect(result.width == 1400)
        #expect(result.height == 1050)
        #expect(result.bytesAfter < result.bytesBefore)
        let header = try Data(contentsOf: result.file).prefix(12)
        #expect(header.prefix(4) == Data("RIFF".utf8) && header.suffix(4) == Data("WEBP".utf8))
        #expect(!(try Data(contentsOf: result.file)).contains(Data("GPS".utf8)))
    }

    @Test func neverUpscales() throws {
        let result = try PhotoProcessor.process(try photo(width: 800, height: 600))
        #expect(result.width == 800)
    }

    @Test func keysFollowTheUploadsLayout() {
        let date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        #expect(PhotoProcessor.key(for: URL(fileURLWithPath: "/x/Café à Noite.HEIC"), in: SiteConfig().photoFolder(date: date)) == "uploads/2026/10/cafe-a-noite.webp")
        #expect(Slug.make("IMG_2041") == "img-2041")
    }
}
