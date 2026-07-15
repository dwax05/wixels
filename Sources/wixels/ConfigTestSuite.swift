import Foundation
import WixelsKit

func runConfigTestSuite() -> Int32 {
    do {
        let legacy = try Config.parse("[[widget]]\nkind = \"clock\"")
        try expect(legacy.theme == nil && legacy.entries[0].theme == nil && legacy.entries[0].enabled,
                   "missing theme and enabled select defaults")

        let disabled = try Config.parse("[[widget]]\nkind = \"clock\"\nenabled = false")
        try expect(!disabled.entries[0].enabled, "explicit enabled=false parses")

        let malformedEnabled = try Config.parse("[[widget]]\nkind = \"clock\"\nenabled = \"no\"")
        try expect(malformedEnabled.entries[0].enabled, "malformed enabled defaults to true")

        let selected = try Config.parse("""
        [theme]
        default = "macos"
        [[widget]]
        kind = "clock"
        [[widget]]
        kind = "stats"
        theme = "cynaberii"
        """)
        try expect(selected.theme == "macos", "global theme parses")
        try expect(selected.entries[1].theme == "cynaberii", "widget theme override parses")

        let malformed = try Config.parse("""
        [theme]
        default = "Not Valid"
        [[widget]]
        kind = "clock"
        theme = "also_bad"
        """)
        try expect(malformed.theme == nil && malformed.entries[0].theme == nil,
                   "malformed theme IDs are ignored")

        let explicit = try Config.parse("""
        [[widget]]
        kind = "clock"
        anchor = "bottomLeft"
        offset = [4, 5]
        """).entries[0]
        let base = WixelsKit.Placement(anchor: .topCenter, offset: .zero,
                                       size: .init(width: 10, height: 20))
        let placed = explicit.placement.apply(to: base)
        try expect(placed.anchor == .bottomLeft && placed.offset.width == 4 && placed.size == base.size,
                   "explicit placement fields override widget defaults selectively")

        let malformedPlacement = try Config.parse("""
        [[widget]]
        kind = "clock"
        offset = ["left", 5]
        size = [10, "tall"]
        """).entries[0].placement.apply(to: base)
        try expect(malformedPlacement.offset == base.offset && malformedPlacement.size == base.size,
                   "malformed placement values leave widget defaults intact")

        let menuConfig = try Config.parse("""
        [[widget]]
        kind = "clock"
        [[widget]]
        kind = "clock"
        enabled = false
        [[widget]]
        kind = "missing"
        """)
        let menu = widgetMenuEntries(config: menuConfig, registered: ["clock", "owl", "stats"])
        try expect(menu.map(\.label) == ["clock", "clock #2", "owl", "stats"] &&
                   menu.map(\.enabled) == [true, false, false, false] &&
                   menu[2].sourceIndex == nil && menu[3].sourceIndex == nil,
                   "menu includes unconfigured registered widgets as disabled entries")

        let colorConfig = try Config.parse("""
        [colors]
        file = "/tmp/wal.json"
        background = "#102021"
        foreground = "F3E9D2"
        color0 = "#1A2C2D"
        color15 = "ABCDEF"
        unknown = "harmless"
        """).colors
        try expect(colorConfig.file == "/tmp/wal.json" &&
                   colorConfig.overrides.background == RGB(hex: "102021") &&
                   colorConfig.overrides.foreground == RGB(hex: "F3E9D2") &&
                   colorConfig.overrides.accents[0] == RGB(hex: "1A2C2D") &&
                   colorConfig.overrides.accents[15] == RGB(hex: "ABCDEF"),
                   "direct [colors] values parse with and without #")

        let partialColors = try Config.parse("""
        [colors]
        background = "bad"
        color2 = 3
        color3 = "001122"
        """).colors
        try expect(partialColors.file == nil && partialColors.overrides.background == nil &&
                   partialColors.overrides.accents[2] == nil &&
                   partialColors.overrides.accents[3] == RGB(hex: "001122"),
                   "malformed [colors] values are ignored independently")

        let obsoletePath = try Config.parse("""
        [paths]
        colors = "/tmp/obsolete.json"
        """).colors
        try expect(obsoletePath.file == nil, "legacy [paths].colors no longer configures palette")

        let tempPath = "/tmp/wixels-config-tests-\(ProcessInfo.processInfo.processIdentifier).toml"
        try """
        [theme]
        default = "cynaberii"
        [[widget]]
        kind = "clock"
        theme = "macos"
        anchor = "bottomLeft"
        offset = [4, 5]
        mystery = "keep me"
          [widget.options]
          answer = 42
        """.write(toFile: tempPath, atomically: true, encoding: .utf8)
        setenv("WIXELS_CONFIG", tempPath, 1)
        defer { unsetenv("WIXELS_CONFIG"); try? FileManager.default.removeItem(atPath: tempPath) }
        Config.writeWidgetToggle(sourceIndex: 0, kind: "clock", enabled: false)
        let preserved = try String(contentsOfFile: tempPath, encoding: .utf8)
        let preservedConfig = Config.load()
        try expect(preserved.contains("enabled = false") && preserved.contains("mystery = 'keep me'") &&
                   preservedConfig.entries[0].placement.offset == CGSize(width: 4, height: 5) &&
                   preservedConfig.entries[0].options.int("answer") == 42,
                   "disabling preserves placement, options, and unknown fields")

        Config.writeWidgetToggle(sourceIndex: nil, kind: "owl", enabled: true)
        let appended = try String(contentsOfFile: tempPath, encoding: .utf8)
        try expect(appended.contains("kind = 'owl'") && !appended.contains("enabled = true"),
                   "enabling an absent widget writes a minimal entry")
        print("PASS config suite")
        return 0
    } catch {
        print("FAIL config suite: \(error)")
        return 1
    }
}

private struct ConfigTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ConfigTestFailure(description: message) }
    print("PASS \(message)")
}
