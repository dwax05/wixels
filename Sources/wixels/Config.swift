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
    /// The ordinal of this `[[widget]]` block in the source TOML. This survives
    /// entries the host cannot mount (for example, a missing plugin), so a drag
    /// always writes back to the block that produced this entry.
    let sourceIndex: Int
    let kind: String
    let theme: String?
    let placement: PlacementOverride
    let options: Options
}

/// The whole parsed config: the widget list plus the app-global `[paths]` (raw as
/// written — `Paths.resolve` tilde-expands them; nil = use the built-in default).
/// Per-widget files (quotes, disk-snail volume) live in each widget's
/// `[widget.options]`, not here.
struct LoadedConfig {
    var entries: [ConfigEntry] = []
    var theme: String?
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

/// A placement change made by layout edit mode. `anchor == nil` means a normal
/// drag changed only the offset; reset supplies the plugin's default anchor too.
struct PlacementChange {
    let configIndex: Int
    let anchor: WixelsKit.Anchor?
    let offset: CGSize
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
        let theme = validThemeID(table["theme"]?.table?["default"]?.string)
        let entries: [ConfigEntry] = (table["widget"]?.array).map(Array.init)?.enumerated().compactMap { index, item in
            guard let t = item.table, let kind = t["kind"]?.string else { return nil }
            return ConfigEntry(sourceIndex: index, kind: kind, theme: validThemeID(t["theme"]?.string),
                               placement: placement(from: t), options: options(from: t))
        } ?? []
        return LoadedConfig(entries: entries, theme: theme,
                            colors: paths?["colors"]?.string,
                            nowplaying: paths?["nowplaying"]?.string)
    }

    private static func validThemeID(_ id: String?) -> String? {
        guard let id, ThemeManifest.isValidID(id) else {
            if let id, !id.isEmpty { Log.note("invalid theme id '\(id)' — ignoring") }
            return nil
        }
        return id
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

    /// Persist dragged positions by regenerating the TOML from its parsed document.
    /// This deliberately trades comments/formatting for a simple, reliable write path
    /// while retaining every parsed table, option, and unknown field.
    static func writePlacements(_ changes: [PlacementChange]) {
        guard !changes.isEmpty,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text),
              let widgets = table["widget"]?.array else { return }
        for change in changes {
            let index = change.configIndex
            guard index >= 0, index < widgets.count,
                  let widget = widgets[index]?.table else { continue }
            if let anchor = change.anchor { widget["anchor"] = anchor.rawValue }
            let value = TOMLArray()
            value.append(Int(change.offset.width))
            value.append(Int(change.offset.height))
            widget["offset"] = value
        }

        let out = table.convert(to: .toml)
        if (try? out.write(toFile: path, atomically: true, encoding: .utf8)) == nil {
            Log.note("failed to write offsets to \(path)")
        }
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
