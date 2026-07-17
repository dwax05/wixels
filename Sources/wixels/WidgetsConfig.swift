import Foundation
import SwiftUI
import TOMLKit
import WixelsKit

enum VariableKind: Equatable, Sendable { case poll(interval: TimeInterval), listen }

struct VariableDefinition: Sendable {
    let name: String
    let command: String
    let kind: VariableKind
    let initial: String
}

/// A deliberately small, typed representation of widgets.toml. TOMLKit stays in
/// this file: rendering never has to inspect untrusted TOML values.
struct DeclarativeWidgetDefinition: Sendable {
    let id: String
    let placement: Placement
    let style: WidgetStyle
    let visible: ValueBinding
    let root: DeclarativeNode
}

indirect enum DeclarativeNode: Sendable {
    case text(ValueBinding, style: WidgetStyle, visible: ValueBinding, action: DeclarativeAction?)
    case image(ValueBinding, style: WidgetStyle, visible: ValueBinding, action: DeclarativeAction?)
    case row([DeclarativeNode], spacing: Double, style: WidgetStyle, visible: ValueBinding)
    case column([DeclarativeNode], spacing: Double, style: WidgetStyle, visible: ValueBinding)
    case stack([DeclarativeNode], style: WidgetStyle, visible: ValueBinding)
    case spacer(length: Double?, visible: ValueBinding)
}

struct DeclarativeStyle: Sendable { let value: WidgetStyle }
struct DeclarativeAction: Sendable { let command: String }

/// Literal strings interpolate `{variable}`. Visibility additionally accepts
/// `true`, `false`, `{name}`, `name`, `name == value`, and `name != value`.
struct ValueBinding: Equatable, Sendable {
    let source: String
    let visibility: Bool
    static let always = ValueBinding(source: "true", visibility: true)

    func resolve(in values: [String: String]) -> String { interpolate(source, values: values) }
    func isVisible(in values: [String: String]) -> Bool {
        guard visibility else { return true }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return true }; if trimmed == "false" { return false }
        let parts = trimmed.components(separatedBy: " != ")
        if parts.count == 2 { return value(parts[0], values) != parts[1] }
        let equal = trimmed.components(separatedBy: " == ")
        if equal.count == 2 { return value(equal[0], values) == equal[1] }
        let actual = value(trimmed, values)
        return !(actual.isEmpty || actual == "0" || actual.lowercased() == "false")
    }
    private func value(_ raw: String, _ values: [String: String]) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("{"), key.hasSuffix("}") {
            let variable = String(key.dropFirst().dropLast())
            return values[variable] ?? ""
        }
        return values[key] ?? key
    }
}

struct LoadedWidgetsConfig {
    var variables: [VariableDefinition] = []
    var widgets: [DeclarativeWidgetDefinition] = []
    var files: [String] = []
    var styles: [String: DeclarativeStyle] = [:]
}

enum WidgetsConfig {
    static var path: String { Paths.resolve(env: "WIXELS_WIDGETS_CONFIG", config: nil, default: "~/.config/wixels/widgets.toml") }

    static func load() -> LoadedWidgetsConfig {
        do { return try load(path: path) }
        catch { Log.note("widgets.toml parse error (\(error)) — ignoring declarative widgets"); return .init(files: [path]) }
    }

    static func parse(_ text: String) throws -> LoadedWidgetsConfig {
        try parse(text, source: path, inherited: .init())
    }

    static func load(path: String) throws -> LoadedWidgetsConfig {
        try load(path: URL(fileURLWithPath: path).standardizedFileURL.path, chain: [], inherited: .init())
    }

    private static func load(path: String, chain: [String], inherited: LoadedWidgetsConfig) throws -> LoadedWidgetsConfig {
        guard !chain.contains(path) else { throw ConfigError.includeCycle(path) }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { throw ConfigError.unreadable(path) }
        var result = try parse(text, source: path, inherited: inherited)
        let table = try TOMLTable(string: text)
        for include in table["include"]?.array ?? [] {
            guard let relative = include.string, !relative.isEmpty else { throw ConfigError.invalidInclude(path) }
            let resolved = URL(fileURLWithPath: relative, relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent()).standardizedFileURL.path
            result = try load(path: resolved, chain: chain + [path], inherited: result)
        }
        if !result.files.contains(path) { result.files.insert(path, at: 0) }
        return result
    }

    private static func parse(_ text: String, source: String, inherited: LoadedWidgetsConfig) throws -> LoadedWidgetsConfig {
        let table = try TOMLTable(string: text)
        var result = inherited
        if !result.files.contains(source) { result.files.append(source) }
        var names = Set(result.variables.map(\.name)), ids = Set(result.widgets.map(\.id))
        for item in table["variable"]?.array ?? [] {
            guard let row = item.table, let name = row["name"]?.string, ThemeManifest.isValidID(name),
                  let raw = row["command"]?.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { Log.note("invalid widgets.toml variable — skipping"); continue }
            guard names.insert(name).inserted else { throw ConfigError.duplicateVariable(name) }
            let kind: VariableKind
            switch row["kind"]?.string ?? "poll" {
            case "poll":
                let interval = row["interval"]?.double ?? row["interval"]?.int.map(Double.init) ?? 60
                guard interval.isFinite, interval >= 1 else { Log.note("invalid widgets.toml interval for '\(name)' — skipping"); continue }
                kind = .poll(interval: interval)
            case "listen": kind = .listen
            default: Log.note("unknown widgets.toml variable kind for '\(name)' — skipping"); continue
            }
            result.variables.append(.init(name: name, command: raw, kind: kind, initial: row["initial"]?.string ?? ""))
        }
        var presets = result.styles
        if let styles = table["style"]?.table {
            for name in styles.keys where ThemeManifest.isValidID(name) {
                if let row = styles[name]?.table { presets[name] = .init(value: .default.applying(WidgetStylePatch.parse(from: row, context: "style.\(name)"))) }
            }
        }
        result.styles = presets
        for item in table["widget"]?.array ?? [] {
            guard let row = item.table, let id = row["id"]?.string, ThemeManifest.isValidID(id) else { Log.note("invalid widgets.toml widget — skipping"); continue }
            guard ids.insert(id).inserted else { throw ConfigError.duplicateWidget(id) }
            let style = resolveStyle(row, presets: presets, context: "widget.\(id)")
            var placement = PlacementTOML.placement(from: row, logging: true).apply(to: .init(anchor: .bottomLeft, offset: .init(width: 24, height: 24), size: .init(width: 260, height: 80), sizing: .fitContent))
            if let sizing = row["sizing"]?.string {
                switch sizing {
                case "fixed": placement.sizing = .fixed
                case "fit-content": placement.sizing = .fitContent
                default: Log.note("unknown widgets.toml sizing '\(sizing)' for widget '\(id)' — using fit-content")
                }
            }
            let visible = binding(row["visible"], visibility: true, context: id)
            let root: DeclarativeNode
            if let legacy = row["text"]?.string { root = .text(.init(source: legacy, visibility: false), style: style, visible: .always, action: action(row)) }
            else if let rootRow = row["root"]?.table { root = try node(rootRow, presets: presets, inheritedStyle: style, context: "widget.\(id).root") }
            else { throw ConfigError.malformedNode("widget '\(id)' requires text or [widget.root]") }
            result.widgets.append(.init(id: id, placement: placement, style: style, visible: visible, root: root))
        }
        return result
    }

    private static func node(_ row: TOMLTable, presets: [String: DeclarativeStyle], inheritedStyle: WidgetStyle, context: String) throws -> DeclarativeNode {
        guard let type = row["type"]?.string else { throw ConfigError.malformedNode("\(context): missing type") }
        let style = resolveStyle(row, presets: presets, base: inheritedStyle, context: context)
        let visible = binding(row["visible"], visibility: true, context: context)
        let action = action(row)
        let children = try (row["children"]?.array ?? []).enumerated().map { index, value -> DeclarativeNode in
            guard let child = value.table else { throw ConfigError.malformedNode("\(context).children[\(index)]") }
            return try node(child, presets: presets, inheritedStyle: style, context: "\(context).children[\(index)]")
        }
        switch type {
        case "text": guard let value = row["value"]?.string ?? row["text"]?.string else { throw ConfigError.malformedNode("\(context): text requires value") }; return .text(.init(source: value, visibility: false), style: style, visible: visible, action: action)
        case "image": guard let value = row["value"]?.string ?? row["src"]?.string else { throw ConfigError.malformedNode("\(context): image requires src") }; return .image(.init(source: value, visibility: false), style: style, visible: visible, action: action)
        case "row": return .row(children, spacing: spacing(row), style: style, visible: visible)
        case "column": return .column(children, spacing: spacing(row), style: style, visible: visible)
        case "stack": return .stack(children, style: style, visible: visible)
        case "spacer": return .spacer(length: row["length"].flatMap(PlacementTOML.number).map(Double.init), visible: visible)
        default: throw ConfigError.malformedNode("\(context): unknown type '\(type)'")
        }
    }

    private static func spacing(_ row: TOMLTable) -> Double { max(0, row["spacing"].flatMap(PlacementTOML.number).map(Double.init) ?? 0) }
    private static func action(_ row: TOMLTable) -> DeclarativeAction? { row["on-click"]?.string.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .init(command: $0) } }
    private static func binding(_ raw: TOMLValueConvertible?, visibility: Bool, context: String) -> ValueBinding { .init(source: raw?.string ?? (visibility ? "true" : ""), visibility: visibility) }
    private static func resolveStyle(_ row: TOMLTable, presets: [String: DeclarativeStyle], base: WidgetStyle = .default, context: String) -> WidgetStyle {
        var style = base
        if let name = row["style"]?.string { if let preset = presets[name] { style = preset.value } else { Log.note("unknown widgets.toml style '\(name)' for \(context)") } }
        return style.applying(WidgetStylePatch.parse(from: row, context: context))
    }

    private enum ConfigError: Error, CustomStringConvertible {
        case unreadable(String), invalidInclude(String), includeCycle(String), duplicateWidget(String), duplicateVariable(String), malformedNode(String)
        var description: String { switch self { case .unreadable(let p): "cannot read \(p)"; case .invalidInclude(let p): "invalid include in \(p)"; case .includeCycle(let p): "include cycle at \(p)"; case .duplicateWidget(let id): "duplicate widget id '\(id)'"; case .duplicateVariable(let n): "duplicate variable '\(n)'"; case .malformedNode(let m): m } }
    }
}
