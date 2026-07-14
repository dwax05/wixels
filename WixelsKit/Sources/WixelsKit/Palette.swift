// Palette value types — the colour model widgets draw with. Shared across the
// plugin ABI, so `public`. The live file-watching store that produces these
// (PaletteStore) is host-only and lives in the executable target.
//
// Colours are kept as RGB (0…255 components), not SwiftUI Color, so widgets can
// derive shades with `mix`/`shade` exactly like the Übersicht widgets' hex
// helpers. `.color` bridges to SwiftUI at draw time.

import SwiftUI

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double   // 0…255

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF); g = Double((v >> 8) & 0xFF); b = Double(v & 0xFF)
    }

    public var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    /// Linear interpolate toward `o` by `t` (0…1) — the JS `mix(a,b,t)`.
    public func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    /// Multiply each channel by `f` (darken <1 / lighten >1) — the JS `shade(a,f)`.
    public func shade(_ f: Double) -> RGB { RGB(r * f, g * f, b * f) }

    /// Non-failable hex parse for hardcoded literals — falls back to neutral grey
    /// instead of trapping if a constant is ever mistyped.
    public static func from(_ hex: String) -> RGB { RGB(hex: hex) ?? RGB(120, 120, 120) }
}

public struct Palette: Equatable, Sendable {
    public var background: RGB
    public var foreground: RGB
    public var accents: [RGB]          // color0…15

    public init(background: RGB, foreground: RGB, accents: [RGB]) {
        self.background = background; self.foreground = foreground; self.accents = accents
    }

    /// color-N with clamping (the JS reads `c.colorN` with `||` fallbacks).
    public func c(_ i: Int) -> RGB { accents[max(0, min(accents.count - 1, i))] }

    public static let fallback = Palette(
        background: RGB(10, 25, 25), foreground: RGB(193, 197, 197),
        accents: (0..<16).map { _ in RGB(120, 120, 120) }
    )
}
