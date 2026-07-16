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
    /// Stable identity used by the group-local layout file. Nil rows acquire one
    /// the first time their group is laid out.
    let id: String?
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

/// A fully resolved placement stored outside desktop.toml. The source index is
/// used only while migrating legacy rows; the on-disk key is `id`.
struct LayoutRecord {
    let configIndex: Int
    let id: String
    let placement: Placement
}

struct LayoutWrite {
    let group: String
    let records: [LayoutRecord]
    /// All configured rows resolved to this group, including disabled/unavailable
    /// ones. This lets legacy folder-less rows migrate correctly.
    var memberIndexes: Set<Int> = []
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
            guard let t = item.table, let kind = t["kind"]?.string.flatMap(validKind) else { return nil }
            return ConfigEntry(sourceIndex: index, kind: kind, id: validID(t["id"]?.string), folder: folder(from: t), enabled: enabled(from: t),
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

    /// A kind is either bare (accepted as-is, matching every existing config) or a
    /// namespaced `"suite/kind"` pair whose segments must both be kebab-case IDs.
    private static func validKind(_ kind: String) -> String? {
        guard kind.contains("/") else { return kind }
        let parts = kind.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(ThemeManifest.isValidID) else {
            Log.note("invalid widget kind '\(kind)' — expected \"kind\" or \"namespace/kind\"; skipping")
            return nil
        }
        return kind
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

    private static func validID(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return id
    }

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

    /// One group's rows in file order: the ordinal, kind, and any explicit `id`.
    private typealias IDRow = (index: Int, kind: String, id: String?)

    /// Assign IDs within one group: existing IDs are never changed; id-less rows
    /// get `kind`, `kind-2`, … in file order. Mount-time resolution (`stableIDs`)
    /// and migration (`writeLayouts`) share this so a row can never mount under
    /// one ID and be written under another.
    private static func assignIDs(rows: [IDRow]) -> [Int: String] {
        var result: [Int: String] = [:], used = Set<String>()
        for row in rows {
            guard let id = row.id else { continue }
            result[row.index] = id; used.insert(id)
        }
        for row in rows where row.id == nil {
            var n = 1, candidate = row.kind
            while used.contains(candidate) { n += 1; candidate = "\(row.kind)-\(n)" }
            result[row.index] = candidate; used.insert(candidate)
        }
        return result
    }

    /// Assign deterministic IDs within each plugin group. Existing IDs are never
    /// changed, so duplicate widget rows survive reordering and package switches.
    static func stableIDs(entries: [ConfigEntry], groups: [Int: String]) -> [Int: String] {
        var rowsByGroup: [String: [IDRow]] = [:]
        for entry in entries {
            guard let group = groups[entry.sourceIndex] else { continue }
            rowsByGroup[group, default: []].append((entry.sourceIndex, entry.kind, entry.id))
        }
        return rowsByGroup.values.reduce(into: [:]) { result, rows in
            result.merge(assignIDs(rows: rows)) { current, _ in current }
        }
    }

    /// Write group-scoped layout files. On a group's first write, migrate its
    /// desktop rows: assign stable IDs and remove legacy placement fields.
    static func writeLayouts(_ writes: [LayoutWrite]) {
        guard !writes.isEmpty,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let table = try? TOMLTable(string: text),
              let widgets = table["widget"]?.array else { return }
        var generatedIDs: [Int: String] = [:], migratedIndexes = Set<Int>()
        for write in writes {
            // A missing ID is the migration marker. Repeating this idempotent
            // pass also repairs a desktop.toml restored after its layout file.
            var rows: [IDRow] = []
            for index in 0..<widgets.count {
                guard let row = widgets[index]?.table, rowBelongsToGroup(row, index: index, write: write),
                      let kind = row["kind"]?.string else { continue }
                migratedIndexes.insert(index)
                rows.append((index, kind, validID(row["id"]?.string)))
            }
            let assigned = assignIDs(rows: rows)
            for row in rows where row.id == nil { generatedIDs[row.index] = assigned[row.index] }
            LayoutStore.write(group: write.group, records: write.records)
        }
        // TOMLKit intentionally exposes no public table-key deletion API. Remove
        // placement assignments only from widget rows migrated in this write.
        var output: [String] = [], widgetIndex = -1, inWidgetRoot = false
        for line in table.convert(to: .toml).split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed == "[[widget]]" {
                widgetIndex += 1
                inWidgetRoot = true
                output.append(String(line))
                if let id = generatedIDs[widgetIndex] { output.append("id = '\(id)'") }
                continue
            }
            // Sub-tables like [widget.options] may hold keys named like placement
            // fields; only the widget row's own top-level assignments migrate.
            if trimmed.hasPrefix("[") { inWidgetRoot = false }
            if inWidgetRoot, migratedIndexes.contains(widgetIndex), ["anchor =", "offset =", "size =", "zBoost =", "align ="].contains(where: trimmed.hasPrefix) { continue }
            output.append(String(line))
        }
        let out = output.joined(separator: "\n") + "\n"
        if (try? out.write(toFile: path, atomically: true, encoding: .utf8)) == nil {
            Log.note("failed to migrate layout fields in \(path)")
        }
    }

    private static func rowGroup(_ row: TOMLTable) -> String { folder(from: row) ?? "Ungrouped" }
    private static func rowBelongsToGroup(_ row: TOMLTable, index: Int, write: LayoutWrite) -> Bool {
        write.memberIndexes.contains(index) || rowGroup(row) == write.group
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
    /// discovered widget, without changing unrecognised config entries or explicit
    /// per-row theme overrides. Package themes resolve at mount time.
    static func writeExclusiveWidgetGroup(selected: Set<PluginWidget>,
                                          configured: [Int: PluginWidget]) {
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
