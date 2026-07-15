// Config — the desktop layout, read from TOML at launch.
//
// `~/.config/wixels/desktop.toml` (override with WIXELS_CONFIG) lists `[[widget]]`
// blocks: a kind, optional placement fields, and an optional `[widget.options]`
// table. Missing placement fields fall back to the widget spec's default, so a
// minimal block is just `kind = "..."`. Order in the file is mount order (= z-stack
// among same-level widgets). Unknown kinds are skipped by the resolver in main.
//
// A top-level `[colors]` table configures the optional wal palette file and
// individual palette overrides. Per-widget files stay in `[widget.options]`.
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
    /// Nil is a legacy row; it resolves to the first loaded folder for its kind.
    let folder: String?
    let enabled: Bool
    let theme: String?
    let placement: PlacementOverride
    let options: Options
}

/// Palette configuration remains sparse until a themed widget resolves it against
/// its selected theme's defaults.
struct ColorConfiguration {
    var file: String?
    var overrides: PaletteOverrides = .init()
}

/// The whole parsed config: the widget list plus the app-global `[colors]` table.
/// File paths are raw — `Paths.resolve` tilde-expands them; nil uses the pywal default.
/// Per-widget files (quotes, disk-snail volume) live in each widget's
/// `[widget.options]`, not here.
struct LoadedConfig {
    var entries: [ConfigEntry] = []
    var theme: String?
    var colors = ColorConfiguration()
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

    static func selectedPluginFolder() -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text) else { return nil }
        guard let folder = table["plugins"]?.table?["activeFolder"]?.string,
              !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return folder
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
        let colors = colorConfiguration(from: table["colors"]?.table)
        let theme = validThemeID(table["theme"]?.table?["default"]?.string)
        let entries: [ConfigEntry] = (table["widget"]?.array).map(Array.init)?.enumerated().compactMap { index, item in
            guard let t = item.table, let kind = t["kind"]?.string else { return nil }
            return ConfigEntry(sourceIndex: index, kind: kind, folder: folder(from: t), enabled: enabled(from: t),
                               theme: validThemeID(t["theme"]?.string),
                               placement: placement(from: t), options: options(from: t))
        } ?? []
        return LoadedConfig(entries: entries, theme: theme, colors: colors)
    }

    private static func colorConfiguration(from table: TOMLTable?) -> ColorConfiguration {
        guard let table else { return .init() }
        var result = ColorConfiguration(file: table["file"]?.string)
        result.overrides.background = color(table["background"], named: "background")
        result.overrides.foreground = color(table["foreground"], named: "foreground")
        for index in 0..<16 {
            result.overrides.accents[index] = color(table["color\(index)"], named: "color\(index)")
        }
        return result
    }

    private static func color(_ value: TOMLValueConvertible?, named name: String) -> RGB? {
        guard let value else { return nil }
        guard let string = value.string, let rgb = RGB(hex: string) else {
            Log.note("invalid [colors].\(name) value — ignoring")
            return nil
        }
        return rgb
    }

    private static func validThemeID(_ id: String?) -> String? {
        guard let id, ThemeManifest.isValidID(id) else {
            if let id, !id.isEmpty { Log.note("invalid theme id '\(id)' — ignoring") }
            return nil
        }
        return id
    }

    private static func enabled(from t: TOMLTable) -> Bool {
        guard let value = t["enabled"] else { return true }
        guard let bool = value.bool else {
            Log.note("invalid widget enabled value — defaulting to enabled")
            return true
        }
        return bool
    }

    private static func folder(from t: TOMLTable) -> String? { folder(from: t, key: "folder") }

    private static func folder(from t: TOMLTable?, key: String) -> String? {
        guard let value = t?[key] else { return nil }
        guard let folder = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !folder.isEmpty else {
            Log.note("invalid widget folder — ignoring")
            return nil
        }
        return folder
    }

    private static func placement(from t: TOMLTable) -> PlacementOverride {
        var o = PlacementOverride()
        if let a = t["anchor"]?.string { o.anchor = WixelsKit.Anchor(rawValue: a) }
        if let off = t["offset"]?.array, off.count >= 2 {
            let values = Array(off)
            if let x = number(values[0]), let y = number(values[1]) {
                o.offset = CGSize(width: x, height: y)
            } else {
                Log.note("invalid widget offset — ignoring")
            }
        }
        if let sz = t["size"]?.array, sz.count >= 2 {
            let values = Array(sz)
            if let width = number(values[0]), let height = number(values[1]) {
                o.size = CGSize(width: width, height: height)
            } else {
                Log.note("invalid widget size — ignoring")
            }
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

    /// Persist a menu toggle while retaining every other field in the source TOML.
    /// An absent registered kind gets only a kind field, inheriting global defaults.
    static func writeWidgetToggle(sourceIndex: Int?, kind: String, folder: String, themeID: String?, enabled: Bool) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text) else {
            Log.note("failed to read config before toggling '\(kind)'")
            return
        }
        if let sourceIndex,
           let widgets = table["widget"]?.array,
           sourceIndex >= 0, sourceIndex < widgets.count,
            let widget = widgets[sourceIndex]?.table {
            widget["enabled"] = enabled
            if enabled, let themeID { widget["theme"] = themeID }
        } else {
            let widget = TOMLTable()
            widget["kind"] = kind
            widget["folder"] = folder
            if let themeID { widget["theme"] = themeID }
            if !enabled { widget["enabled"] = false }
            if let widgets = table["widget"]?.array {
                widgets.append(widget)
            } else {
                let widgets = TOMLArray()
                widgets.append(widget)
                table["widget"] = widgets
            }
        }
        let out = table.convert(to: .toml)
        if (try? out.write(toFile: path, atomically: true, encoding: .utf8)) == nil {
            Log.note("failed to write widget toggle to \(path)")
        }
    }

    /// Enable every widget in one discovered menu group and disable every other
    /// discovered widget, without changing unrecognised config entries.
    static func writeExclusiveWidgetGroup(selected: Set<PluginWidget>,
                                          configured: [Int: PluginWidget],
                                          themeIDsByGroup: [String: String]) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text) else {
            Log.note("failed to read config before selecting widget folder")
            return
        }
        let widgets = table["widget"]?.array
        let existing = Set(configured.values)
        for (index, item) in (widgets.map(Array.init) ?? []).enumerated() {
            guard let widget = item.table, let identity = configured[index] else { continue }
            widget["enabled"] = selected.contains(identity)
            if selected.contains(identity), let themeID = themeIDsByGroup[identity.group] {
                widget["theme"] = themeID
            }
        }
        let missing = selected.subtracting(existing).sorted { lhs, rhs in
            lhs.group == rhs.group ? lhs.kind < rhs.kind : lhs.group < rhs.group
        }
        if !missing.isEmpty {
            let destination: TOMLArray
            if let widgets { destination = widgets }
            else { destination = TOMLArray(); table["widget"] = destination }
            for identity in missing {
                let widget = TOMLTable()
                widget["kind"] = identity.kind
                widget["folder"] = identity.group
                if let themeID = themeIDsByGroup[identity.group] { widget["theme"] = themeID }
                destination.append(widget)
            }
        }
        let out = table.convert(to: .toml)
        if (try? out.write(toFile: path, atomically: true, encoding: .utf8)) == nil {
            Log.note("failed to write widget folder selection to \(path)")
        }
    }

    static func writeActivePluginFolder(_ folder: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text) else {
            Log.note("failed to read config before selecting plugin folder")
            return
        }
        let plugins: TOMLTable
        if let existing = table["plugins"]?.table { plugins = existing }
        else { plugins = TOMLTable() }
        plugins["activeFolder"] = folder
        table["plugins"] = plugins
        let out = table.convert(to: .toml)
        if (try? out.write(toFile: path, atomically: true, encoding: .utf8)) == nil {
            Log.note("failed to write active plugin folder to \(path)")
        }
    }

    private static func number(_ value: TOMLValueConvertible) -> CGFloat? {
        if let number = value.double, number.isFinite { return CGFloat(number) }
        if let integer = value.int { return CGFloat(integer) }
        return nil
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
