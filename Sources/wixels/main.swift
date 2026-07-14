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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: WidgetHost!

    func applicationDidFinishLaunching(_ note: Notification) {
        let services = Services()                          // shared samplers (cpu, music)
        let host = WidgetHost(palette: PaletteStore())
        // Index the catalog by kind, then mount each enabled entry in config order
        // (order sets z-stacking among same-level widgets — frog before clock).
        let specs = Dictionary(catalog(services).map { ($0.kind, $0) },
                               uniquingKeysWith: { first, _ in first })
        for entry in desktopConfig() {
            guard let spec = specs[entry.kind] else { continue }   // unknown kind: skip
            spec.mount(host, entry.override ?? spec.defaultPlacement)
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
