import Foundation
import SwiftUI
import TOMLKit
import WixelsKit

enum VariableKind: Equatable, Sendable {
    case poll(interval: TimeInterval)
    case listen
}

struct VariableDefinition: Sendable {
    let name: String
    let command: String
    let kind: VariableKind
    let initial: String
}

struct TextWidgetDefinition: Sendable {
    let id: String
    let text: String
    let placement: Placement
    let style: WidgetStyle
}

struct LoadedWidgetsConfig {
    var variables: [VariableDefinition] = []
    var widgets: [TextWidgetDefinition] = []
}

enum WidgetsConfig {
    static var path: String {
        Paths.resolve(env: "WIXELS_WIDGETS_CONFIG", config: nil,
                      default: "~/.config/wixels/widgets.toml")
    }

    static func load() -> LoadedWidgetsConfig {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .init() }
        do { return try parse(text) }
        catch { Log.note("widgets.toml parse error (\(error)) — ignoring script widgets"); return .init() }
    }

    static func parse(_ text: String) throws -> LoadedWidgetsConfig {
        let table = try TOMLTable(string: text)
        var result = LoadedWidgetsConfig(), names = Set<String>(), ids = Set<String>()
        for item in table["variable"]?.array ?? [] {
            guard let row = item.table,
                  let name = row["name"]?.string, ThemeManifest.isValidID(name),
                  let rawCommand = row["command"]?.string,
                  let command = Optional(rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)), !command.isEmpty,
                  !names.contains(name) else { Log.note("invalid or duplicate widgets.toml variable — skipping"); continue }
            let kind: VariableKind
            switch row["kind"]?.string ?? "poll" {
            case "poll":
                let interval = row["interval"]?.double ?? row["interval"]?.int.map(Double.init) ?? 60
                guard interval.isFinite, interval >= 1 else { Log.note("invalid widgets.toml interval for '\(name)' — skipping"); continue }
                kind = .poll(interval: interval)
            case "listen":
                if row["interval"] != nil { Log.note("widgets.toml variable '\(name)': interval is ignored for kind = \"listen\"") }
                kind = .listen
            case let other:
                Log.note("unknown widgets.toml variable kind '\(other)' for '\(name)' — skipping"); continue
            }
            names.insert(name)
            result.variables.append(.init(name: name, command: command, kind: kind,
                                          initial: row["initial"]?.string ?? ""))
        }
        var presets: [String: WidgetStylePatch] = [:]
        if let styles = table["style"]?.table {
            for name in styles.keys {
                guard ThemeManifest.isValidID(name), let styleRow = styles[name]?.table
                else { Log.note("invalid widgets.toml style table '\(name)' — skipping"); continue }
                presets[name] = WidgetStylePatch.parse(from: styleRow, context: "style.\(name)")
            }
        }
        for item in table["widget"]?.array ?? [] {
            guard let row = item.table,
                  let id = row["id"]?.string, ThemeManifest.isValidID(id), !ids.contains(id),
                  let text = row["text"]?.string else { Log.note("invalid or duplicate widgets.toml widget — skipping"); continue }
            let override = PlacementTOML.placement(from: row, logging: true)
            let placement = override.apply(to: .init(anchor: .bottomLeft, offset: .init(width: 24, height: 24), size: .init(width: 260, height: 80), sizing: .fitContent))
            var style = WidgetStyle.default
            if let presetName = row["style"]?.string {
                if let preset = presets[presetName] { style = style.applying(preset) }
                else { Log.note("unknown widgets.toml style '\(presetName)' for widget '\(id)' — using defaults") }
            } else if row["style"]?.table != nil {
                Log.note("widgets.toml widget '\(id)': style must be a preset name; put override keys directly on the widget")
            }
            style = style.applying(WidgetStylePatch.parse(from: row, context: "widget.\(id)"))
            ids.insert(id); result.widgets.append(.init(id: id, text: text, placement: placement, style: style))
        }
        return result
    }
}
