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
        let menu = widgetMenuEntries(config: menuConfig, available: [
            PluginWidget(group: "Clocks", kind: "clock"),
            PluginWidget(group: "Pets", kind: "owl"),
            PluginWidget(group: "Ungrouped", kind: "stats"),
        ])
        try expect(menu.map(\.label) == ["clock", "clock #2", "owl", "stats"] &&
                   menu.map(\.enabled) == [true, false, false, false] &&
                   menu.map(\.group) == ["Clocks", "Clocks", "Pets", "Ungrouped"] &&
                   menu[2].sourceIndex == nil && menu[3].sourceIndex == nil,
                   "menu groups configured and unconfigured registered widgets")

        let duplicateFolders = try Config.parse("""
        [[widget]]
        kind = "clock"
        folder = "Home"
        [[widget]]
        kind = "clock"
        folder = "Work"
        enabled = false
        """)
        let duplicateMenu = widgetMenuEntries(config: duplicateFolders, available: [
            PluginWidget(group: "Home", kind: "clock"),
            PluginWidget(group: "Work", kind: "clock"),
        ])
        try expect(duplicateMenu.map(\.group) == ["Home", "Work"] &&
                   duplicateMenu.map(\.label) == ["clock", "clock"] &&
                   duplicateMenu.map(\.enabled) == [true, false],
                   "same plugin kind in separate folders remains separate")

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
        Config.writeWidgetToggle(sourceIndex: 0, kind: "clock", folder: "Cynaberii", themeID: "cynaberii", enabled: false)
        let preserved = try String(contentsOfFile: tempPath, encoding: .utf8)
        let preservedConfig = Config.load()
        try expect(preserved.contains("enabled = false") && preserved.contains("mystery = 'keep me'") &&
                   preservedConfig.entries[0].placement.offset == CGSize(width: 4, height: 5) &&
                   preservedConfig.entries[0].options.int("answer") == 42,
                   "disabling preserves placement, options, and unknown fields")

        Config.writeWidgetToggle(sourceIndex: nil, kind: "owl", folder: "Cynaberii", themeID: "cynaberii", enabled: true)
        let appended = try String(contentsOfFile: tempPath, encoding: .utf8)
        try expect(appended.contains("kind = 'owl'") && appended.contains("folder = 'Cynaberii'") &&
                   !appended.contains("enabled = true"),
                   "enabling an absent widget writes a foldered minimal entry")

        Config.writeExclusiveWidgetGroup(selected: [
            PluginWidget(group: "Cynaberii", kind: "clock"),
            PluginWidget(group: "Cynaberii", kind: "stats"),
        ], configured: [
            0: PluginWidget(group: "Cynaberii", kind: "clock"),
            1: PluginWidget(group: "Cynaberii", kind: "owl"),
        ], themeIDsByGroup: ["Cynaberii": "cynaberii"])
        let exclusive = Config.load()
        try expect(exclusive.entries.first(where: { $0.kind == "clock" })?.enabled == true &&
                   exclusive.entries.first(where: { $0.kind == "owl" })?.enabled == false &&
                   exclusive.entries.first(where: { $0.kind == "stats" })?.enabled == true &&
                   exclusive.entries.first(where: { $0.kind == "clock" })?.theme == "cynaberii" &&
                   exclusive.entries.first(where: { $0.kind == "clock" })?.options.int("answer") == 42,
                   "folder selection enables selected kinds, disables others, and preserves fields")

        Config.writeActivePluginFolder("Cynaberii")
        let activeFolder = Config.selectedPluginFolder()
        try expect(activeFolder == "Cynaberii",
                   "active plugin folder persists independently of widget settings")

        let cynGroup = "Cynaberii-\(ProcessInfo.processInfo.processIdentifier)"
        let macGroup = "Macos-\(ProcessInfo.processInfo.processIdentifier)"
        try """
        [[widget]]
        kind = "clock"
        folder = "\(cynGroup)"
        anchor = "bottomLeft"
        offset = [4, 5]
        [[widget]]
        kind = "clock"
        folder = "\(cynGroup)"
        offset = [40, 50]
        [[widget]]
        kind = "clock"
        folder = "\(macGroup)"
        offset = [80, 90]
        [[widget]]
        kind = "clock"
        offset = [120, 130]
        """.write(toFile: tempPath, atomically: true, encoding: .utf8)
        let grouped = Config.load()
        let groups = [0: cynGroup, 1: cynGroup, 2: macGroup, 3: "Ungrouped"]
        let ids = Config.stableIDs(entries: grouped.entries, groups: groups)
        try expect(ids == [0: "clock", 1: "clock-2", 2: "clock", 3: "clock"],
                   "stable IDs are deterministic per group for duplicate kinds")
        let cynPlacement = Placement(anchor: .topLeft, offset: .init(width: 21, height: 22),
                                     size: .init(width: 123, height: 45), zBoost: 3, align: .leading)
        let macPlacement = Placement(anchor: .bottomRight, offset: .init(width: 31, height: 32),
                                     size: .init(width: 222, height: 99))
        let ungroupedPlacement = Placement(anchor: .center, offset: .init(width: 41, height: 42),
                                           size: .init(width: 100, height: 100))
        Config.writeLayouts([
            .init(group: cynGroup, records: [
                .init(configIndex: 0, id: ids[0]!, placement: cynPlacement),
                .init(configIndex: 1, id: ids[1]!, placement: cynPlacement),
            ]),
            .init(group: macGroup, records: [.init(configIndex: 2, id: ids[2]!, placement: macPlacement)]),
            .init(group: "Ungrouped", records: [.init(configIndex: 3, id: ids[3]!, placement: ungroupedPlacement)]),
        ])
        let fallback = Placement(anchor: .topLeft)
        let layouts = (LayoutStore.load(group: cynGroup)["clock"]?.apply(to: fallback),
                       LayoutStore.load(group: macGroup)["clock"]?.apply(to: fallback),
                       LayoutStore.load(group: "Ungrouped")["clock"]?.apply(to: fallback))
        let migratedText = try String(contentsOfFile: tempPath, encoding: .utf8)
        let migrated = Config.load()
        try expect(layouts.0?.offset == cynPlacement.offset && layouts.1?.offset == macPlacement.offset &&
                   layouts.2?.offset == ungroupedPlacement.offset && LayoutStore.filename(for: cynGroup) != LayoutStore.filename(for: macGroup),
                   "independent group layout files keep same-kind placements separate")
        try expect(migrated.entries.prefix(2).map(\.id) == ["clock", "clock-2"] &&
                   !migratedText.contains("anchor =") && !migratedText.contains("offset ="),
                   "first group layout save assigns IDs and migrates legacy placement fields")
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
