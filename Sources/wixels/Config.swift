// Config — the desktop layout, read from TOML at launch.
//
// `~/.config/wixels/desktop.toml` (override with WIXELS_CONFIG) lists `[[widget]]`
// blocks: a kind, optional placement fields, and an optional `[widget.options]`
// table. Missing placement fields fall back to the widget spec's default, so a
// minimal block is just `kind = "..."`. Order in the file is mount order (= z-stack
// among same-level widgets). Unknown kinds are skipped by the resolver in main.
//
// A top-level `[paths]` table sets app-global data files (colors = wal palette,
// nowplaying = music cache); those are threaded into PaletteStore/MusicMonitor in
// main. Precedence for each: env var (WIXELS_COLORS/WIXELS_NOWPLAYING) > `[paths]` >
// built-in default. Per-widget files stay in that widget's `[widget.options]`.
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

/// The whole parsed config: the widget list plus the app-global `[paths]` (raw as
/// written — `Paths.resolve` tilde-expands them; nil = use the built-in default).
/// Per-widget files (quotes, disk-snail volume) live in each widget's
/// `[widget.options]`, not here.
struct LoadedConfig {
    var entries: [ConfigEntry] = []
    var colors: String?          // wal palette file (PaletteStore)
    var nowplaying: String?      // music cache file (MusicMonitor)
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
        Paths.resolve(env: "WIXELS_CONFIG", config: nil,
                      default: "~/.config/wixels/desktop.toml")
    }

    /// Load the config file, falling back to the bundled default when it's missing
    /// or unparseable (logged, never fatal).
    static func load() -> LoadedConfig {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            Log.note("no config at \(path) — using built-in default layout")
            return (try? parse(defaultTOML)) ?? LoadedConfig()
        }
        do { return try parse(text) }
        catch {
            Log.note("config parse error (\(error)) — using built-in default layout")
            return (try? parse(defaultTOML)) ?? LoadedConfig()
        }
    }

    static func parse(_ text: String) throws -> LoadedConfig {
        let table = try TOMLTable(string: text)
        let paths = table["paths"]?.table
        let entries: [ConfigEntry] = (table["widget"]?.array).map(Array.init)?.compactMap { item in
            guard let t = item.table, let kind = t["kind"]?.string else { return nil }
            return ConfigEntry(kind: kind, placement: placement(from: t), options: options(from: t))
        } ?? []
        return LoadedConfig(entries: entries,
                            colors: paths?["colors"]?.string,
                            nowplaying: paths?["nowplaying"]?.string)
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

    /// The TOML `align` strings, mapped like `Anchor(rawValue:)` does for anchors —
    /// a lookup table rather than a hand-written switch (SwiftUI's `Alignment` isn't
    /// `RawRepresentable`, so this is the nearest equivalent).
    private static let alignments: [String: Alignment] = [
        "leading": .leading, "trailing": .trailing, "center": .center,
        "top": .top, "bottom": .bottom,
        "topLeading": .topLeading, "topTrailing": .topTrailing,
        "bottomLeading": .bottomLeading, "bottomTrailing": .bottomTrailing,
    ]

    private static func alignment(_ s: String) -> Alignment? { alignments[s] }

}
