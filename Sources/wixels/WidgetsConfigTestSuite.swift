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
        try widgetsConfigExpect(interpolate(config.widgets[0].text, values: ["quote": "hello"]) == "lorem hello ipsum" &&
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

private struct WidgetsConfigTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
