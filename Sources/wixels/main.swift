// wixels — entry point.
//
// A native macOS desktop-widget agent replacing the cynaberii Übersicht widgets.
// The whole app is: build a host, load the widget plugins, resolve the TOML config
// against the registered specs, mount, run. Everything else (windows, desktop layer,
// palette, scheduling, occlusion) lives behind WidgetHost.
//
// Widgets are plugin dylibs (Sources/Widget*/), each registering its spec via a
// @_cdecl shim. The layout lives in ~/.config/wixels/desktop.toml. This file never
// needs touching to add or rearrange a widget.
//
// Run:  cd ~/Developer/wixels && swift run
// Quit: Ctrl-C.

import AppKit
import WixelsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: WidgetHost!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ note: Notification) {
        // Read the TOML layout (scaffolds a default on first run). Its `[paths]` feed
        // the shared samplers + palette store; env vars still override (see Config).
        Config.writeDefaultIfMissing()
        let cfg = Config.load()

        let services = Services(nowplayingPath: cfg.nowplaying)   // shared samplers (cpu, music)
        let host = WidgetHost(palette: PaletteStore(colorsPath: cfg.colors))

        // Build the spec table entirely from plugin dylibs — every widget is a
        // libWidget*.dylib the loader dlopens and registers (no static built-ins).
        let registrar = Registrar()
        PluginLoader.load(into: registrar)

        // Mount each enabled entry in file order (order sets z-stacking among
        // same-level widgets — frog before clock).
        for entry in cfg.entries {
            if let spec = registrar.specs[entry.kind] {
                let placement = entry.placement.apply(to: spec.defaultPlacement)
                host.mount(spec.build(services, entry.options), placement: placement,
                           defaultPlacement: spec.defaultPlacement, configIndex: entry.sourceIndex)
            } else if registrar.themedSpecs[entry.kind] != nil,
                      let resolved = registrar.resolveThemed(kind: entry.kind,
                          themeID: entry.theme ?? cfg.theme ?? "macos",
                          services: services, options: entry.options) {
                let placement = entry.placement.apply(to: resolved.placement)
                host.mount(resolved.widget, placement: placement, defaultPlacement: resolved.placement,
                           configIndex: entry.sourceIndex)
            } else {
                Log.note("no widget for kind '\(entry.kind)'")
            }
        }
        host.run()
        self.host = host

        // Menu bar presence: shows the app is up and toggles widgets at runtime.
        self.statusBar = StatusBarController(host: host)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // no dock icon, single process
if CommandLine.arguments.contains("--config-tests") {
    exit(runConfigTestSuite())
} else if CommandLine.arguments.contains("--layout-tests") {
    exit(runLayoutTestSuite())
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
