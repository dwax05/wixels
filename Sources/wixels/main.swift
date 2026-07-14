// wixels — entry point.
//
// A native macOS desktop-widget agent replacing the cynaberii Übersicht widgets.
// The whole app is: build a host, resolve the desktop config against the catalog,
// mount, run. Everything else (windows, desktop layer, palette, scheduling,
// occlusion) lives behind WidgetHost.
//
// The two files a user edits:
//   Desktop.swift   — which widgets are on + where (see desktopConfig()).
//   Widgets/*.swift — a widget's own struct + its `spec` (default placement).
// This file just wires them together and never needs touching to add a widget.
//
// Run:  cd ~/Developer/wixels && swift run
// Quit: Ctrl-C.

import AppKit
import WixelsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: WidgetHost!

    func applicationDidFinishLaunching(_ note: Notification) {
        let services = Services()                          // shared samplers (cpu, music)
        let host = WidgetHost(palette: PaletteStore())

        // Build the spec table: the still-static built-ins, then the plugin dylibs
        // (clock + stats today; all of them by phase 4).
        let registrar = Registrar()
        for spec in catalog() { registrar.add(spec) }
        PluginLoader.load(into: registrar)

        // Read the TOML layout (scaffolds a default on first run), then build+mount
        // each enabled entry in file order (order sets z-stacking among same-level
        // widgets — frog before clock).
        Config.writeDefaultIfMissing()
        for entry in Config.load() {
            guard let spec = registrar.specs[entry.kind] else {
                FileHandle.standardError.write(Data("wixels: no widget for kind '\(entry.kind)'\n".utf8))
                continue
            }
            let placement = entry.placement.apply(to: spec.defaultPlacement)
            let mountable = spec.build(services, entry.options)
            host.mount(mountable, placement: placement)
        }
        host.run()
        self.host = host
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // no dock icon, single process
let delegate = AppDelegate()
app.delegate = delegate
app.run()
