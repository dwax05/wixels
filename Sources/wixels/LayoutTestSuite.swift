import AppKit
import WixelsKit

/// Integration coverage for the production layout seam. This loads the user's
/// real plugin set and options, mounts every widget at its plugin default, and
/// injects a no-op writer so the suite cannot modify desktop configuration.
@MainActor
func runLayoutTestSuite() -> Int32 {
    let config = Config.load()
    let services = Services()
    let registrar = Registrar()
    PluginLoader.load(into: registrar)
    let host = WidgetHost(palette: PaletteStore(colorsPath: config.colors),
                          placementWriter: { _ in })

    for entry in config.entries {
        if let spec = registrar.specs[entry.kind] {
            host.mount(spec.build(services, entry.options), placement: spec.defaultPlacement,
                       defaultPlacement: spec.defaultPlacement, configIndex: entry.sourceIndex)
        } else if let resolved = registrar.resolveThemed(kind: entry.kind,
            themeID: entry.theme ?? config.theme ?? "macos",
            services: services, options: entry.options) {
            host.mount(resolved.widget, placement: resolved.placement,
                       defaultPlacement: resolved.placement, configIndex: entry.sourceIndex)
        }
    }

    host.run()
    pumpWindowServer()
    let before = host.layoutSnapshot()
    host.resetLayout()
    pumpWindowServer()
    let after = host.layoutSnapshot()

    guard !before.isEmpty, before.count == after.count else {
        print("FAIL layout reset mounted \(before.count) production windows before and \(after.count) after")
        return 1
    }

    var failures = 0
    for expected in before {
        guard let actual = after.first(where: { $0.configIndex == expected.configIndex }) else {
            print("FAIL \(expected.kind)[\(expected.configIndex)] disappeared during reset")
            failures += 1
            continue
        }
        guard actual.frame == expected.frame else {
            let dx = actual.frame.origin.x - expected.frame.origin.x
            let dy = actual.frame.origin.y - expected.frame.origin.y
            print("FAIL \(expected.kind)[\(expected.configIndex)] moved dx=\(dx) dy=\(dy) " +
                  "before=\(NSStringFromRect(expected.frame)) after=\(NSStringFromRect(actual.frame))")
            failures += 1
            continue
        }
        print("PASS \(expected.kind)[\(expected.configIndex)] frame unchanged")
    }

    print(failures == 0 ? "PASS production layout reset suite" :
          "FAIL production layout reset suite: \(failures) shifted window(s)")
    return failures == 0 ? 0 : 1
}

@MainActor
private func pumpWindowServer() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
}
