import AppKit
import SwiftUI
import WixelsKit
@testable import WidgetStats

@main
struct WidgetStatsTests {
    @MainActor static func main() throws {
        let border = RGB(160, 150, 200)
        var accents = (0..<16).map { _ in RGB(100, 95, 130) }
        accents[4] = border
        let palette = Palette(background: RGB(15, 12, 30), foreground: RGB(225, 220, 240),
                              accents: accents)
        let theme = ThemeContext(definition: fixtureTheme(id: "pixel", rectangle: true), palette: palette)
        let stats = StatsView(s: .init(cpu: 0, mem: 42, battery: 100,
                                      charging: false, plugged: false), theme: theme)
        let intrinsic = ImageRenderer(content: stats)
        intrinsic.scale = 1
        let macosStats = StatsView(s: .init(cpu: 0, mem: 42, battery: 100,
                                           charging: false, plugged: false),
                                   theme: ThemeContext(definition: fixtureTheme(id: "native", rectangle: false), palette: palette))
        let macosIntrinsic = ImageRenderer(content: macosStats)
        macosIntrinsic.scale = 1
        let placement = Stats.spec().defaultPlacement.size
        for size in [intrinsic.nsImage?.size, macosIntrinsic.nsImage?.size].compactMap({ $0 }) {
            guard size.width <= placement.width, size.height <= placement.height else {
                throw Failure("Stats placement \(placement) clips intrinsic card \(size)")
            }
        }
        let view = stats
            .frame(width: placement.width, height: placement.height, alignment: .trailing)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let data = renderer.nsImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
            throw Failure("could not render StatsView")
        }

        let midpoint = bitmap.pixelsHigh / 2
        let firstHalf = longestBorderRun(in: 0..<midpoint, bitmap: bitmap, target: border)
        let secondHalf = longestBorderRun(in: midpoint..<bitmap.pixelsHigh, bitmap: bitmap, target: border)
        guard firstHalf >= 150, secondHalf >= 150 else {
            throw Failure("pane must draw both horizontal edges (runs: \(firstHalf), \(secondHalf))")
        }
        print("PASS stats pane draws all four edges")
    }

    private static func longestBorderRun(in rows: Range<Int>, bitmap: NSBitmapImageRep,
                                         target: RGB) -> Int {
        var longest = 0
        for y in rows {
            var run = 0
            for x in 0..<bitmap.pixelsWide {
                if matches(bitmap.colorAt(x: x, y: y), target) {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
            }
        }
        return longest
    }

    private static func matches(_ color: NSColor?, _ target: RGB) -> Bool {
        guard let c = color?.usingColorSpace(.deviceRGB) else { return false }
        return abs(c.redComponent * 255 - target.r) < 24 &&
               abs(c.greenComponent * 255 - target.g) < 24 &&
               abs(c.blueComponent * 255 - target.b) < 24 && c.alphaComponent > 0.9
    }
}

private func fixtureTheme(id: String, rectangle: Bool) -> ThemeDefinition {
    let color: ThemeColor = .rgb(RGB(160, 150, 200))
    return ThemeDefinition(manifest: .init(id: id, name: id), tokens: .init(
        colors: .init(background: color, foreground: color, secondary: color, accent: color, alternateAccent: color,
            positive: color, warning: color, negative: color, muted: color, border: color, shadow: color),
        typography: .init(title: .init(size: 12), body: .init(size: 11), label: .init(size: 10), caption: .init(size: 9), symbol: .init(size: 12)),
        card: .init(fill: .color(color), shape: rectangle ? .rectangle : .rounded(16), borderWidth: rectangle ? 4 : 1,
            shadowX: rectangle ? 4 : 0, shadowY: rectangle ? 4 : 0), mediaShape: rectangle ? .rectangle : .rounded(8)),
        defaultPalette: .fallback)
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
