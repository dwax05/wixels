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
    // The spec table is built once from plugin dylibs — reloads reuse it (dylibs are
    // dlopen'd at launch; they aren't re-scanned).
    private let registrar = Registrar()
    private var host: WidgetHost!
    private var statusBar: StatusBarController!
    private var watcher: ConfigWatcher?

    func applicationDidFinishLaunching(_ note: Notification) {
        Config.writeDefaultIfMissing()
        PluginLoader.load(into: registrar)

        buildSession()
        self.statusBar = StatusBarController(host: host) { [weak self] info in
            self?.toggle(info)
        }
        // Watch the layout file and rebuild live when it changes (WIXELS_CONFIG honoured).
        self.watcher = ConfigWatcher(path: Config.path) { [weak self] in self?.reload() }
    }

    /// Construct a host from the current config and mount every widget. Reads `[colors]`
    /// afresh so a config edit to colors/nowplaying takes effect on reload. Called at
    /// launch and again on every reload.
    private func buildSession() {
        // TOML colors override each value from the selected palette file; WIXELS_COLORS
        // replaces only that file selection (see PaletteStore).
        let cfg = Config.load()
        let menuEntries = makeMenuEntries(config: cfg)
        let services = Services()                                  // shared samplers (cpu, music)
        let host = WidgetHost(
            palette: PaletteStore(colorsPath: cfg.colors.file, overrides: cfg.colors.overrides),
            menuEntries: menuEntries,
            // Suppress the file event our own drag-save write would otherwise raise.
            placementWriter: { [weak self] changes in
                self?.watcher?.ignoringWrites { Config.writePlacements(changes) }
            }
        )

        // Mount each entry in file order (order sets z-stacking among same-level
        // widgets — frog before clock).
        for entry in cfg.entries {
            guard entry.enabled else { continue }
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
    }

    /// Configured rows retain file order. Unknown config entries remain in the
    /// config file, but are omitted until their plugin is loaded again.
    private func makeMenuEntries(config: LoadedConfig) -> [WidgetInfo] {
        let registered = Set(registrar.specs.keys).union(registrar.themedSpecs.keys)
        var seen: [String: Int] = [:]
        var result: [WidgetInfo] = []
        for entry in config.entries where registered.contains(entry.kind) {
            let n = (seen[entry.kind] ?? 0) + 1
            seen[entry.kind] = n
            result.append(WidgetInfo(sourceIndex: entry.sourceIndex, kind: entry.kind,
                                     label: n == 1 ? entry.kind : "\(entry.kind) #\(n)",
                                     enabled: entry.enabled))
        }
        return result
    }

    private func toggle(_ info: WidgetInfo) {
        guard let host else { return }
        let on = !info.enabled
        watcher?.ignoringWrites {
            Config.writeWidgetToggle(sourceIndex: info.sourceIndex, kind: info.kind, enabled: on)
        }
        host.shutdown()
        buildSession()
        statusBar?.rebind(host: self.host)
    }

    /// Config file changed on disk: tear the running host down and rebuild it. Skipped
    /// while the user is dragging widgets in layout-edit mode (exiting edit writes the
    /// config itself, which is self-suppressed).
    private func reload() {
        guard let host else { return }
        guard !host.editing else {
            Log.note("config changed during layout edit — ignoring")
            return
        }
        Log.note("config changed — reloading")
        host.shutdown()
        buildSession()
        statusBar.rebind(host: self.host)
    }
}

if CommandLine.arguments.contains("--config-tests") {
    exit(runConfigTestSuite())
} else if CommandLine.arguments.contains("--layout-tests") {
    exit(runLayoutTestSuite())
} else if CommandLine.arguments.contains("--interaction-tests") {
    exit(runInteractionTestSuite())
} else if CommandLine.arguments.contains("--plugin-tests") {
    exit(PluginLoader.runTestSuite())
} else if CommandLine.arguments.contains("--plugin-path-tests") {
    exit(runPluginLoaderPathTestSuite())
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)      // no dock icon, single process
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
