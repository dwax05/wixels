import AppKit
import SwiftUI

/// Rasterized, one-pixel-per-cell sprite artwork.  Keeping the raster here means
/// animation changes only a layer's `contents`; SwiftUI never redraws the grid.
@MainActor
public enum SpriteImages {
    private static let cache = NSCache<NSString, CGImageBox>()

    public static func image(for sprite: Sprite, palette: [Character: Color]) -> CGImage? {
        let key = cacheKey(sprite: sprite, palette: palette)
        if let cached = cache.object(forKey: key as NSString) { return cached.image }
        guard let image = makeImage(sprite: sprite, palette: palette) else { return nil }
        cache.setObject(CGImageBox(image), forKey: key as NSString)
        return image
    }

    private static func cacheKey(sprite: Sprite, palette: [Character: Color]) -> String {
        let colors = palette.keys.sorted { String($0) < String($1) }.map { ch in
            let c = NSColor(palette[ch]!).usingColorSpace(.sRGB) ?? NSColor(palette[ch]!)
            return "\(ch):\(c.redComponent),\(c.greenComponent),\(c.blueComponent),\(c.alphaComponent)"
        }.joined(separator: ";")
        return sprite.joined(separator: "\n") + "|" + colors
    }

    private static func makeImage(sprite: Sprite, palette: [Character: Color]) -> CGImage? {
        let width = sprite.first?.count ?? 0
        guard width > 0, !sprite.isEmpty else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: sprite.count,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setShouldAntialias(false)
        for (row, line) in sprite.enumerated() {
            for (col, ch) in line.enumerated() where palette[ch] != nil {
                context.setFillColor(NSColor(palette[ch]!).cgColor)
                // CGContext has a bottom-left origin; sprites conventionally don't.
                context.fill(CGRect(x: col, y: sprite.count - row - 1, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }
}

private final class CGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
