import Foundation

func runPluginLoaderPathTestSuite() -> Int32 {
    let dirs = PluginLoader.searchDirs(
        bundleResourceURL: URL(fileURLWithPath: "/Applications/Wixels.app/Contents/Resources"),
        homeDirectory: URL(fileURLWithPath: "/Users/tester"))
    let expected = [
        "/Applications/Wixels.app/Contents/Resources/plugins",
        "/Applications/Wixels.app/Contents/Resources/themes",
        "/Users/tester/.config/wixels/plugins",
        "/Users/tester/.config/wixels/themes"
    ]
    guard dirs == expected else {
        print("FAIL plugin loader paths: \(dirs)")
        return 1
    }

    let staged = PluginLoader.searchDirs(
        bundleResourceURL: URL(fileURLWithPath: "/ignored/resources"),
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        developmentRoot: URL(fileURLWithPath: "/tmp/wixels-stage"))
    guard staged == ["/tmp/wixels-stage/plugins", "/tmp/wixels-stage/themes",
                     "/Users/tester/.config/wixels/plugins", "/Users/tester/.config/wixels/themes"] else {
        print("FAIL plugin loader development paths: \(staged)")
        return 1
    }

    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("wixels-loader-test-\(UUID().uuidString)")
    let first = temp.appendingPathComponent("plugins")
    let second = temp.appendingPathComponent("themes")
    do {
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for name in ["libWidgetZ.dylib", "libWidgetA.dylib", "libUnrelated.dylib"] {
            try Data().write(to: first.appendingPathComponent(name))
        }
        let nested = first.appendingPathComponent("Cynaberii")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("libWidgetNested.dylib"))
        try Data().write(to: second.appendingPathComponent("libWidgetA.dylib"))
        let firstFiles = PluginLoader.loadableFiles(in: first.path)
        let secondFiles = PluginLoader.loadableFiles(in: second.path)
        guard firstFiles == ["Cynaberii/libWidgetNested.dylib", "libWidgetA.dylib", "libWidgetZ.dylib"],
              secondFiles == ["libWidgetA.dylib"] else {
            print("FAIL plugin loader sorting/filtering")
            return 1
        }
        guard PluginLoader.folder(for: "Cynaberii/nested/libWidgetNested.dylib") == "Cynaberii" &&
              PluginLoader.folder(for: "libWidgetA.dylib") == PluginLoader.ungrouped else {
            print("FAIL plugin loader folder grouping")
            return 1
        }
        guard PluginLoader.folder(for: "mypackage/libThemeCynaberii.dylib") == "mypackage" &&
              PluginLoader.folder(for: "mypackage/libWidgetPet.dylib") == "mypackage" &&
              PluginLoader.belongsToSelectedFolder("mypackage/libThemeCynaberii.dylib", selectedFolder: "mypackage") &&
              PluginLoader.belongsToSelectedFolder("mypackage/libWidgetPet.dylib", selectedFolder: "mypackage") else {
            print("FAIL package theme and widget grouping")
            return 1
        }
        guard PluginLoader.belongsToSelectedFolder("MyDesk/libWidgetClock.dylib", selectedFolder: "mydesk") &&
              !PluginLoader.belongsToSelectedFolder("Elsewhere/libWidgetClock.dylib", selectedFolder: "MyDesk") &&
              !PluginLoader.belongsToSelectedFolder("Elsewhere/libThemeElsewhere.dylib", selectedFolder: "MyDesk") else {
            print("FAIL plugin loader folder selection")
            return 1
        }
        var seen = Set<String>()
        let unique = (firstFiles + secondFiles).filter { seen.insert($0).inserted }
        guard unique == ["Cynaberii/libWidgetNested.dylib", "libWidgetA.dylib", "libWidgetZ.dylib"] else {
            print("FAIL plugin loader duplicate suppression")
            return 1
        }
        let quarantined = first.appendingPathComponent("libWidgetZ.dylib").path
        guard setxattr(quarantined, "com.apple.quarantine", "0083;test;wixels;", 17, 0, 0) == 0 else {
            print("FAIL quarantine fixture: setxattr")
            return 1
        }
        let flagged = Quarantine.flaggedExtensions(in: [first.path, second.path])
        guard flagged == [quarantined] else {
            print("FAIL quarantine detection: \(flagged)")
            return 1
        }
        guard Quarantine.strip(flagged).isEmpty, !Quarantine.isFlagged(quarantined),
              Quarantine.flaggedExtensions(in: [first.path, second.path]).isEmpty else {
            print("FAIL quarantine strip")
            return 1
        }
    } catch {
        print("FAIL plugin loader fixture: \(error)")
        return 1
    }
    try? FileManager.default.removeItem(at: temp)
    print("PASS plugin loader resource, user, and development paths + quarantine handling")
    return 0
}
