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

/// Build the menu catalog from both configured rows and registered plugin kinds.
/// Configured rows keep their file order (and permit duplicate mounts); registered
/// kinds missing from the config are appended unchecked so users can enable them.
func widgetMenuEntries(config: LoadedConfig, available: Set<PluginWidget>,
                       themeIDsByGroup: [String: String] = [:]) -> [WidgetInfo] {
    let fallbackGroups = Dictionary(grouping: available, by: \.kind).mapValues { $0.map(\.group).min()! }
    var seen: [PluginWidget: Int] = [:]
    var result: [WidgetInfo] = []
    for entry in config.entries {
        guard let group = entry.folder ?? fallbackGroups[entry.kind] else { continue }
        let identity = PluginWidget(group: group, kind: entry.kind)
        guard available.contains(identity) else { continue }
        let n = (seen[identity] ?? 0) + 1
        seen[identity] = n
        result.append(WidgetInfo(sourceIndex: entry.sourceIndex, kind: entry.kind,
                                 label: n == 1 ? entry.kind : "\(entry.kind) #\(n)",
                                 group: group,
                                 themeID: themeIDsByGroup[group],
                                 enabled: entry.enabled))
    }
    for identity in available.subtracting(Set(seen.keys)).sorted(by: {
        $0.group == $1.group ? $0.kind < $1.kind : $0.group < $1.group
    }) {
        result.append(WidgetInfo(sourceIndex: nil, kind: identity.kind, label: identity.kind,
                                 group: identity.group, themeID: themeIDsByGroup[identity.group], enabled: false))
    }
    return result
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The spec table is built once from plugin dylibs — reloads reuse it (dylibs are
    // dlopen'd at launch; they aren't re-scanned).
    private let registrar = Registrar()
    private var pluginCatalog = PluginCatalog()
    private var host: WidgetHost!
    private var statusBar: StatusBarController!
    private var watcher: ConfigWatcher?
    private var gallery: PreviewGalleryController?

    func applicationDidFinishLaunching(_ note: Notification) {
        if CommandLine.arguments.contains("--gallery") {
            _ = PluginLoader.load(into: registrar, excluding: Quarantine.resolveUserExtensions())
            let gallery = PreviewGalleryController(registrar: registrar)
            self.gallery = gallery
            gallery.show()
            return
        }
        Config.writeDefaultIfMissing()
        // Downloaded extension files are quarantined; ask once and clear before any
        // dlopen so approved widgets load in this launch without a restart.
        let excluded = Quarantine.resolveUserExtensions()
        pluginCatalog = PluginLoader.load(into: registrar, excluding: excluded)
        activateSelectedFolderIfNeeded()
        if registrar.specs.isEmpty && registrar.themedSpecs.isEmpty {
            Log.note("no widgets installed — install the matching Cynaberii extension pack in ~/.config/wixels, then restart")
        }

        buildSession()
        self.statusBar = StatusBarController(host: host, folders: pluginCatalog.folders) { [weak self] info in
            self?.toggle(info)
        } selectGroupHandler: { [weak self] group in
            self?.loadOnlyPackage(group: group)
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
            let group = entry.folder ?? pluginCatalog.widgets
                .filter { $0.kind == entry.kind }.map(\.group).min()
            guard let group, pluginCatalog.widgets.contains(PluginWidget(group: group, kind: entry.kind)) else {
                Log.note("no widget for folder '\(entry.folder ?? "(none)")' and kind '\(entry.kind)'")
                continue
            }
            let themeID = pluginCatalog.themeIDsByGroup[group] ?? entry.theme ?? cfg.theme ?? "macos"
            if let spec = registrar.specs[entry.kind] {
                let placement = entry.placement.apply(to: spec.defaultPlacement)
                host.mount(spec.build(services, entry.options), placement: placement,
                           defaultPlacement: spec.defaultPlacement, configIndex: entry.sourceIndex)
            } else if registrar.themedSpecs[entry.kind] != nil,
                      let resolved = registrar.resolveThemed(kind: entry.kind,
                          themeID: themeID,
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
    /// config file, but are omitted until their plugin is loaded again. Registered
    /// kinds without a row are appended unchecked, ready to be enabled.
    private func makeMenuEntries(config: LoadedConfig) -> [WidgetInfo] {
        return widgetMenuEntries(config: config, available: pluginCatalog.widgets,
                                 themeIDsByGroup: pluginCatalog.themeIDsByGroup)
    }

    private func toggle(_ info: WidgetInfo) {
        guard let host else { return }
        let on = !info.enabled
        watcher?.ignoringWrites {
            Config.writeWidgetToggle(sourceIndex: info.sourceIndex, kind: info.kind,
                                     folder: info.group, themeID: info.themeID, enabled: on)
        }
        host.shutdown()
        buildSession()
        statusBar?.rebind(host: self.host)
    }

    /// Persist one package as the active set, then relaunch so conflicting widget
    /// dylibs and its bundled theme are resolved as a unit.
    private func loadOnlyPackage(group: String) {
        guard let host else { return }
        let infos = host.widgetInfos()
        let selected = Set(infos.filter { $0.group == group }.map(\.identity))
        if selected.isEmpty {
            watcher?.ignoringWrites { Config.writeActivePluginFolder(group) }
            restart()
            return
        }
        let configured = Dictionary(uniqueKeysWithValues: infos.compactMap { info in
            info.sourceIndex.map { ($0, info.identity) }
        })
        guard !selected.isEmpty else { return }
        watcher?.ignoringWrites {
            Config.writeExclusiveWidgetGroup(selected: selected, configured: configured,
                                             themeIDsByGroup: Dictionary(infos.compactMap { info in
                info.themeID.map { (info.group, $0) }
            }, uniquingKeysWith: { first, _ in first }))
            Config.writeActivePluginFolder(group)
        }
        restart()
    }

    /// After a restart, the selected package's widgets are now available to the
    /// catalog. Enable them and apply their bundled theme before mounting.
    private func activateSelectedFolderIfNeeded() {
        guard let group = Config.selectedPluginFolder() else { return }
        let infos = makeMenuEntries(config: Config.load())
        let selected = Set(infos.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }.map(\.identity))
        guard !selected.isEmpty else { return }
        let configured = Dictionary(uniqueKeysWithValues: infos.compactMap { info in
            info.sourceIndex.map { ($0, info.identity) }
        })
        Config.writeExclusiveWidgetGroup(selected: selected, configured: configured,
                                         themeIDsByGroup: Dictionary(infos.compactMap { info in
            info.themeID.map { (info.group, $0) }
        }, uniquingKeysWith: { first, _ in first }))
    }

    private func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = Array(CommandLine.arguments.dropFirst())
        process.environment = ProcessInfo.processInfo.environment
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            Log.note("could not restart after switching plugin folder: \(error)")
        }
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
