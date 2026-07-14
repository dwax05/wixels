// Config — the desktop layout, read from TOML at launch.
//
// `~/.config/wixels/desktop.toml` (override with WIXELS_CONFIG) lists `[[widget]]`
// blocks: a kind, optional placement fields, and an optional `[widget.options]`
// table. Missing placement fields fall back to the widget spec's default, so a
// minimal block is just `kind = "..."`. Order in the file is mount order (= z-stack
// among same-level widgets). Unknown kinds are skipped by the resolver in main.
//
// TOMLKit is confined to this file — the parsed result is plain WixelsKit types
// (Placement overrides + Options), so plugins never see a TOML dependency.

import Foundation
import SwiftUI
import WixelsKit
import TOMLKit

/// One resolved `[[widget]]` block: which widget, how to nudge its placement, and
/// its options.
struct ConfigEntry {
    let kind: String
    let placement: PlacementOverride
    let options: Options
}

/// Placement fields the config may override; nil = keep the spec's default.
struct PlacementOverride {
    var anchor: WixelsKit.Anchor?
    var offset: CGSize?
    var size: CGSize?
    var zBoost: Int?
    var align: Alignment?

    func apply(to base: Placement) -> Placement {
        Placement(anchor: anchor ?? base.anchor,
                  offset: offset ?? base.offset,
                  size: size ?? base.size,
                  zBoost: zBoost ?? base.zBoost,
                  align: align ?? base.align)
    }
}

enum Config {
    static var path: String {
        ProcessInfo.processInfo.environment["WIXELS_CONFIG"]
            ?? ("~/.config/wixels/desktop.toml" as NSString).expandingTildeInPath
    }

    /// Load the config file, falling back to the bundled default when it's missing
    /// or unparseable (logged, never fatal).
    static func load() -> [ConfigEntry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            warn("no config at \(path) — using built-in default layout")
            return (try? parse(defaultTOML)) ?? []
        }
        do { return try parse(text) }
        catch {
            warn("config parse error (\(error)) — using built-in default layout")
            return (try? parse(defaultTOML)) ?? []
        }
    }

    static func parse(_ text: String) throws -> [ConfigEntry] {
        let table = try TOMLTable(string: text)
        guard let widgets = table["widget"]?.array else { return [] }
        return Array(widgets).compactMap { item in
            guard let t = item.table, let kind = t["kind"]?.string else { return nil }
            return ConfigEntry(kind: kind, placement: placement(from: t), options: options(from: t))
        }
    }

    private static func placement(from t: TOMLTable) -> PlacementOverride {
        var o = PlacementOverride()
        if let a = t["anchor"]?.string { o.anchor = WixelsKit.Anchor(rawValue: a) }
        if let off = t["offset"]?.array, off.count >= 2 {
            let a = Array(off); o.offset = CGSize(width: num(a[0]), height: num(a[1]))
        }
        if let sz = t["size"]?.array, sz.count >= 2 {
            let a = Array(sz); o.size = CGSize(width: num(a[0]), height: num(a[1]))
        }
        if let z = t["zBoost"]?.int { o.zBoost = z }
        if let al = t["align"]?.string { o.align = alignment(al) }
        return o
    }

    private static func options(from t: TOMLTable) -> Options {
        guard let opts = t["options"]?.table else { return .empty }
        var dict: [String: Options.Value] = [:]
        for key in opts.keys {
            if let v = opts[key], let value = optionValue(v) { dict[key] = value }
        }
        return Options(dict)
    }

    private static func optionValue(_ v: TOMLValueConvertible) -> Options.Value? {
        if let b = v.bool { return .bool(b) }
        if let i = v.int { return .int(i) }
        if let d = v.double { return .double(d) }
        if let s = v.string { return .string(s) }
        if let arr = v.array { return .array(Array(arr).compactMap { optionValue($0) }) }
        return nil
    }

    private static func num(_ v: TOMLValueConvertible) -> CGFloat {
        CGFloat(v.double ?? Double(v.int ?? 0))
    }

    private static func alignment(_ s: String) -> Alignment? {
        switch s {
        case "leading":        return .leading
        case "trailing":       return .trailing
        case "center":         return .center
        case "top":            return .top
        case "bottom":         return .bottom
        case "topLeading":     return .topLeading
        case "topTrailing":    return .topTrailing
        case "bottomLeading":  return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default:               return nil
        }
    }

    private static func warn(_ msg: String) {
        FileHandle.standardError.write(Data("wixels: \(msg)\n".utf8))
    }
}
