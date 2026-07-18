import Foundation
import SwiftUI
import WixelsKit

func runWidgetsConfigTestSuite() -> Int32 {
    do {
        let config = try WidgetsConfig.parse("""
        [style.card]
        radius = 12
        border = { width = 2, color = "color4" }
        inner-border = { width = 1, color = "color6", inset = 3 }
        shadow = { color = "color3", offset = [4, 4], opacity = 0.3 }
        padding = 14
        bg = "background"
        bg-opacity = 0.92
        font-size = 15
        font = "mono"
        text-align = "center"

        [[variable]]
        name = "quote"
        command = "printf 'hello'"
        interval = 30
        initial = "loading"

        [[variable]]
        name = "stream"
        kind = "listen"
        command = "tail -f /tmp/x"

        [[variable]]
        name = "bogus"
        kind = "banana"
        command = "true"

        [[widget]]
        id = "lorem"
        text = "lorem {quote} ipsum"
        style = "card"
        anchor = "bottomLeft"
        offset = [3, 4]
        size = [100, 50]

        [[widget]]
        id = "uptime"
        text = "{quote}"
        style = "card"
        radius = 0

        [[widget]]
        id = "plain"
        text = "x"
        style = "nope"

        [[widget]]
        id = "messy"
        text = "y"
        radius = -5
        bg = "colour99"
        font-weight = "chunky"
        padding = 20
        """)
        try widgetsConfigExpect(config.variables.count == 2 && config.variables[0].kind == .poll(interval: 30) &&
                                config.widgets.count == 4 && config.widgets[0].placement.offset.width == 3,
                                "widgets.toml parses poll variables and text widget placement, skips unknown kinds")
        try widgetsConfigExpect(config.variables[1].kind == .listen,
                                "kind = \"listen\" parses without an interval")
        try widgetsConfigExpect(declarativeText(config.widgets[0].root) == "lorem {quote} ipsum" &&
                                interpolate("{quote}", values: ["quote": "hello"]) == "hello" &&
                                interpolate("{missing}", values: [:]) == "{missing}",
                                "text widgets interpolate known variables and retain unknown placeholders")

        var card = WidgetStyle.default
        card.radius = 12
        card.border = BorderStyle(width: 2, color: .accent(4))
        card.innerBorder = InnerBorderStyle(width: 1, color: .accent(6), inset: 3)
        card.shadow = ShadowStyle(color: .accent(3), offsetX: 4, offsetY: 4, opacity: 0.3, blur: 0)
        card.padding = 14
        card.background = .background
        card.backgroundOpacity = 0.92
        card.fontSize = 15
        card.fontFace = .monospaced
        card.textAlignment = .center
        try widgetsConfigExpect(config.widgets[0].style == card,
                                "style presets parse borders from inline tables")
        var overridden = card
        overridden.radius = 0
        try widgetsConfigExpect(config.widgets[1].style == overridden,
                                "widget top-level keys override the preset, rest inherited")
        try widgetsConfigExpect(config.widgets[2].style == .default,
                                "unknown style preset falls back to defaults")
        var messy = WidgetStyle.default
        messy.padding = 20
        try widgetsConfigExpect(config.widgets[3].style == messy,
                                "invalid style values are dropped per key, valid siblings applied")

        try widgetsConfigExpect(ColorRef.parse("background") == .background &&
                                ColorRef.parse("foreground") == .foreground &&
                                ColorRef.parse("color0") == .accent(0) &&
                                ColorRef.parse("color15") == .accent(15) &&
                                ColorRef.parse("#aabbcc") == .fixed(RGB.from("#aabbcc")),
                                "ColorRef parses palette names, slots and hex")
        try widgetsConfigExpect(ColorRef.parse("color16") == nil && ColorRef.parse("#zzz") == nil &&
                                ColorRef.parse("") == nil,
                                "ColorRef rejects out-of-range slots and malformed values")
        let palette = Palette.fallback
        try widgetsConfigExpect(ColorRef.accent(4).rgb(in: palette) == palette.c(4) &&
                                ColorRef.background.rgb(in: palette) == palette.background,
                                "ColorRef resolves against a palette")

        let tree = try WidgetsConfig.parse("""
        [style.compact]
        padding = 2
        fg = "color2"

        [[widget]]
        id = "tree"
        visible = "online == yes"
        [widget.root]
        type = "column"
        spacing = 4
        children = [
          { type = "text", value = "hello {name}", style = "compact" },
          { type = "row", children = [{ type = "image", src = "/tmp/icon.png" }, { type = "spacer", length = 8 }] }
        ]
        """)
        try widgetsConfigExpect(tree.widgets.count == 1 && tree.widgets[0].visible.isVisible(in: ["online": "yes"]) &&
                                !tree.widgets[0].visible.isVisible(in: ["online": "no"]) &&
                                declarativeText(firstChild(tree.widgets[0].root)!) == "hello {name}",
                                "declarative node trees, style references, and visibility bindings parse")

        let clickable = try WidgetsConfig.parse("""
        [[widget]]
        id = "clickable"
        [widget.root]
        type = "text"
        value = "click me"
        on-click = "open https://example.com"
        """)
        try widgetsConfigExpect(clickable.widgets[0].root.containsAction,
                                "on-click actions mark the node tree as containing an action")

        let inert = try WidgetsConfig.parse("""
        [[widget]]
        id = "inert"
        [widget.root]
        type = "row"
        children = [{ type = "text", value = "no click" }]
        """)
        try widgetsConfigExpect(!inert.widgets[0].root.containsAction,
                                "widgets without on-click report no action")

        let clickableCard = try WidgetsConfig.parse("""
        [[widget]]
        id = "clickable-card"
        [widget.root]
        type = "column"
        on-click = "true"
        children = [{ type = "text", value = "card" }]
        """)
        try widgetsConfigExpect(clickableCard.widgets[0].root.containsAction,
                                "on-click on a container node marks the whole card clickable")

        let listenWithInterval = try WidgetsConfig.parse("""
        [[variable]]
        name = "ignored-interval"
        kind = "listen"
        command = "tail -f /tmp/y"
        interval = 15
        """)
        try widgetsConfigExpect(listenWithInterval.variables.count == 1 &&
                                listenWithInterval.variables[0].kind == .listen,
                                "listen variables parse even when an interval key is present (interval is ignored)")

        let tableStyle = try WidgetsConfig.parse("""
        [[widget]]
        id = "table-style"
        text = "x"
        style = { radius = 12 }
        """)
        try widgetsConfigExpect(tableStyle.widgets[0].style == .default,
                                "table-valued style is ignored, falling back to defaults")

        let ignoredWidgetOnClick = try WidgetsConfig.parse("""
        [[widget]]
        id = "widget-level-click"
        on-click = "open https://example.com"
        [widget.root]
        type = "text"
        value = "no click here"
        """)
        try widgetsConfigExpect(!ignoredWidgetOnClick.widgets[0].root.containsAction,
                                "widget-level on-click is ignored for node-tree widgets; only node-level on-click counts")

        let temporary = "/private/tmp/wixels-widgets-config-suite-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: temporary, withIntermediateDirectories: true)
        let package = "\(temporary)/package.toml", root = "\(temporary)/widgets.toml"
        try "[[widget]]\nid = \"included\"\n[widget.root]\ntype = \"text\"\nvalue = \"from package\"\nstyle = \"shared\"\n".write(toFile: package, atomically: true, encoding: .utf8)
        try "include = [\"package.toml\"]\n[style.shared]\npadding = 7\n[[widget]]\nid = \"root\"\ntext = \"from root\"\n".write(toFile: root, atomically: true, encoding: .utf8)
        let included = try WidgetsConfig.load(path: root)
        let expectedFiles = Set([root, package].map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        try widgetsConfigExpect(included.widgets.map(\.id) == ["root", "included"] &&
                                nodeStyle(included.widgets[1].root)?.padding == 7 &&
                                Set(included.files) == expectedFiles,
                                "includes resolve relative paths, inherit presets, and report every watched file")
        let duplicateRejected: Bool
        do { _ = try WidgetsConfig.parse("[[widget]]\nid = \"same\"\ntext = \"a\"\n[[widget]]\nid = \"same\"\ntext = \"b\""); duplicateRejected = false } catch { duplicateRejected = true }
        try "include = [\"widgets.toml\"]\n".write(toFile: package, atomically: true, encoding: .utf8)
        let cycleRejected: Bool
        do { _ = try WidgetsConfig.load(path: root); cycleRejected = false } catch { cycleRejected = true }
        try widgetsConfigExpect(duplicateRejected && cycleRejected,
                                "duplicate widget IDs and include cycles are rejected")

        let cynaberii = try WidgetsConfig.load(path: "declarative/Cynaberii/widgets.toml")
        try widgetsConfigExpect(cynaberii.widgets.map(\.id) == ["cyn-quotes", "cyn-sysbox", "cyn-weather"] &&
                                cynaberii.files.count == 4 &&
                                cynaberii.widgets.allSatisfy({ isFixed($0.placement) }) &&
                                nodeStyle(cynaberii.widgets[0].root)?.radius == 0,
                                "declarative Cynaberii package loads stable fixed cards and shared styles")
        print("PASS widgets config suite")
        return 0
    } catch {
        print("FAIL widgets config suite: \(error)")
        return 1
    }
}

private func widgetsConfigExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw WidgetsConfigTestFailure(message) }
    print("PASS \(message)")
}

private func declarativeText(_ node: DeclarativeNode) -> String? {
    if case let .text(value, _, _, _) = node { return value.source }
    return nil
}

private func firstChild(_ node: DeclarativeNode) -> DeclarativeNode? {
    if case let .column(children, _, _, _, _) = node { return children.first }
    return nil
}

private func nodeStyle(_ node: DeclarativeNode) -> WidgetStyle? {
    switch node {
    case let .text(_, style, _, _), let .image(_, style, _, _),
         let .row(_, _, style, _, _), let .column(_, _, style, _, _), let .stack(_, style, _, _):
        style
    case .spacer:
        nil
    }
}

private func isFixed(_ placement: Placement) -> Bool {
    if case .fixed = placement.sizing { return true }
    return false
}

private struct WidgetsConfigTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
