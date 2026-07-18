// WidgetStyle — visual styling for widgets.toml text widgets. Presets live in
// [style.<name>] tables; per-widget top-level keys override preset values.
// Colors stay symbolic (ColorRef) until render time so pywal palette swaps
// restyle live without a config reload.

import Foundation
import SwiftUI
import TOMLKit
import WixelsKit

enum ColorRef: Equatable, Sendable {
    case background, foreground, accent(Int), fixed(RGB)

    static func parse(_ raw: String) -> ColorRef? {
        switch raw {
        case "background": return .background
        case "foreground": return .foreground
        default:
            if raw.hasPrefix("color"), let i = Int(raw.dropFirst(5)), (0...15).contains(i) {
                return .accent(i)
            }
            if raw.hasPrefix("#"), let rgb = RGB(hex: raw) { return .fixed(rgb) }
            return nil
        }
    }

    func rgb(in palette: Palette) -> RGB {
        switch self {
        case .background: palette.background
        case .foreground: palette.foreground
        case .accent(let i): palette.c(i)
        case .fixed(let rgb): rgb
        }
    }

    func color(in palette: Palette) -> Color { rgb(in: palette).color }
}

struct BorderStyle: Equatable, Sendable { var width: Double; var color: ColorRef }
struct InnerBorderStyle: Equatable, Sendable { var width: Double; var color: ColorRef; var inset: Double }

// Hard offset silhouette behind the card — the Cynaberii theme's shadow look
// (ThemeCard shadowX/Y with blur 0). blur > 0 softens it into a normal shadow.
struct ShadowStyle: Equatable, Sendable {
    var color: ColorRef
    var offsetX: Double
    var offsetY: Double
    var opacity: Double
    var blur: Double
}

enum WidgetAlignment: String, Equatable, Sendable {
    case leading, center, trailing
    var frameAlignment: Alignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var textAlignment: TextAlignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}

enum FontFace: Equatable, Sendable { case system, monospaced, custom(String) }

struct WidgetStyle: Equatable, Sendable {
    var radius: Double = 12
    var border: BorderStyle? = nil
    var innerBorder: InnerBorderStyle? = nil
    var shadow: ShadowStyle? = nil
    var padding: Double = 14
    var background: ColorRef = .background
    var backgroundOpacity: Double = 0.92
    var maxWidth: Double = 260
    var alignment: WidgetAlignment = .leading
    var foreground: ColorRef = .foreground
    var fontSize: Double? = nil   // nil = system .body, matching the pre-style look
    var fontWeight: Font.Weight = .regular
    var fontFace: FontFace = .system
    var lineSpacing: Double = 4
    var textAlignment: WidgetAlignment = .leading

    static let `default` = WidgetStyle()

    var font: Font {
        let size = fontSize ?? Double(NSFont.systemFontSize)
        switch fontFace {
        case .system:
            // No typography keys at all keeps the exact pre-style .body rendering.
            return fontSize == nil && fontWeight == .regular
                ? .body : .system(size: size, weight: fontWeight)
        case .monospaced:
            return .system(size: size, weight: fontWeight, design: .monospaced)
        case .custom(let name):
            return .custom(name, size: size).weight(fontWeight)
        }
    }

    func applying(_ patch: WidgetStylePatch) -> WidgetStyle {
        var s = self
        if let v = patch.radius { s.radius = v }
        if let v = patch.border { s.border = v }
        if let v = patch.innerBorder { s.innerBorder = v }
        if let v = patch.shadow { s.shadow = v }
        if let v = patch.padding { s.padding = v }
        if let v = patch.background { s.background = v }
        if let v = patch.backgroundOpacity { s.backgroundOpacity = v }
        if let v = patch.maxWidth { s.maxWidth = v }
        if let v = patch.alignment { s.alignment = v }
        if let v = patch.foreground { s.foreground = v }
        if let v = patch.fontSize { s.fontSize = v }
        if let v = patch.fontWeight { s.fontWeight = v }
        if let v = patch.fontFace { s.fontFace = v }
        if let v = patch.lineSpacing { s.lineSpacing = v }
        if let v = patch.textAlignment { s.textAlignment = v }
        return s
    }
}

struct WidgetStylePatch: Sendable {
    var radius: Double?
    var border: BorderStyle?
    var innerBorder: InnerBorderStyle?
    var shadow: ShadowStyle?
    var padding: Double?
    var background: ColorRef?
    var backgroundOpacity: Double?
    var maxWidth: Double?
    var alignment: WidgetAlignment?
    var foreground: ColorRef?
    var fontSize: Double?
    var fontWeight: Font.Weight?
    var fontFace: FontFace?
    var lineSpacing: Double?
    var textAlignment: WidgetAlignment?

    private static let weights: [String: Font.Weight] = [
        "ultralight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular,
        "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black,
    ]

    // Skip-and-log per key: a bad value drops only that key, never the table.
    static func parse(from row: TOMLTable, context: String) -> WidgetStylePatch {
        var p = WidgetStylePatch()
        func bad(_ key: String) { Log.note("invalid widgets.toml '\(key)' in \(context) — ignoring") }
        func number(_ key: String, _ valid: (Double) -> Bool = { _ in true }) -> Double? {
            guard row[key] != nil else { return nil }
            guard let v = row.number(key), v.isFinite, valid(v) else { bad(key); return nil }
            return v
        }
        func colorRef(_ key: String) -> ColorRef? {
            guard let raw = row[key] else { return nil }
            guard let s = raw.string, let ref = ColorRef.parse(s) else { bad(key); return nil }
            return ref
        }
        func align(_ key: String) -> WidgetAlignment? {
            guard let raw = row[key] else { return nil }
            guard let s = raw.string, let a = WidgetAlignment(rawValue: s) else { bad(key); return nil }
            return a
        }
        p.radius = number("radius") { $0 >= 0 }
        p.padding = number("padding") { $0 >= 0 }
        p.backgroundOpacity = number("bg-opacity") { (0...1).contains($0) }
        p.maxWidth = number("max-width") { $0 > 0 }
        p.fontSize = number("font-size") { $0 >= 6 }
        p.lineSpacing = number("line-spacing") { $0 >= 0 }
        p.background = colorRef("bg")
        p.foreground = colorRef("fg")
        p.alignment = align("align")
        p.textAlignment = align("text-align")
        if let raw = row["font-weight"] {
            if let s = raw.string, let w = Self.weights[s] { p.fontWeight = w } else { bad("font-weight") }
        }
        if let raw = row["font"] {
            switch raw.string {
            case "system": p.fontFace = .system
            case "mono": p.fontFace = .monospaced
            case .some(let name) where !name.isEmpty: p.fontFace = .custom(name)
            default: bad("font")
            }
        }
        if let raw = row["border"] {
            if let b = borderParts(raw) { p.border = BorderStyle(width: b.width, color: b.color) }
            else { bad("border") }
        }
        if let raw = row["inner-border"] {
            if let b = borderParts(raw) { p.innerBorder = InnerBorderStyle(width: b.width, color: b.color, inset: b.inset) }
            else { bad("inner-border") }
        }
        if let raw = row["shadow"] {
            if let s = shadowParts(raw) { p.shadow = s } else { bad("shadow") }
        }
        return p
    }

    // { color = "color3", offset = [4, 4], opacity = 0.3, blur = 0 }
    private static func shadowParts(_ raw: TOMLValueConvertible) -> ShadowStyle? {
        guard let t = raw.table else { return nil }
        var x = 4.0, y = 4.0
        if let rawOffset = t["offset"] {
            guard let pair = rawOffset.array, pair.count == 2,
                  let px = pair[0].asDouble, let py = pair[1].asDouble,
                  px.isFinite, py.isFinite else { return nil }
            x = px; y = py
        }
        let opacity = t.number("opacity") ?? 0.3
        let blur = t.number("blur") ?? 0
        guard (0...1).contains(opacity), blur.isFinite, blur >= 0 else { return nil }
        var color: ColorRef = .foreground
        if let rawColor = t["color"] {
            guard let s = rawColor.string, let ref = ColorRef.parse(s) else { return nil }
            color = ref
        }
        return ShadowStyle(color: color, offsetX: x, offsetY: y, opacity: opacity, blur: blur)
    }

    // { width = 2, color = "color4", inset = 3 } — width defaults 1, color foreground, inset 3.
    private static func borderParts(_ raw: TOMLValueConvertible) -> (width: Double, color: ColorRef, inset: Double)? {
        guard let t = raw.table else { return nil }
        let width = t.number("width") ?? 1
        let inset = t.number("inset") ?? 3
        guard width.isFinite, width >= 0, inset.isFinite, inset >= 0 else { return nil }
        var color: ColorRef = .foreground
        if let rawColor = t["color"] {
            guard let s = rawColor.string, let ref = ColorRef.parse(s) else { return nil }
            color = ref
        }
        return (width, color, inset)
    }
}
