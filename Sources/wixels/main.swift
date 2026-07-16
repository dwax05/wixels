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
        // The catalog records bare kinds; a namespaced config row matches on its tail.
        let bareKind = Registrar.bareKind(entry.kind)
        guard let group = entry.folder ?? fallbackGroups[bareKind] else { continue }
        let identity = PluginWidget(group: group, kind: bareKind)
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

/// Theme ownership lives in the installed package, never in a widget's source.
func resolvedThemeID(for entry: ConfigEntry, group: String, catalog: PluginCatalog,
                     globalDefault: String?) -> String {
    entry.theme ?? catalog.themeIDsByGroup[group] ?? globalDefault ?? "macos"
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
    private var layoutWatcher: ConfigWatcher?
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
            Log.note("no widgets installed — install a compatible extension pack in ~/.config/wixels, then restart")
        }

        buildSession()
        self.statusBar = StatusBarController(host: host, folders: pluginCatalog.folders) { [weak self] info in
            self?.toggle(info)
        } selectGroupHandler: { [weak self] group in
            self?.loadOnlyPackage(group: group)
        }
        // Watch the layout file and rebuild live when it changes (WIXELS_CONFIG honoured).
        self.watcher = ConfigWatcher(path: Config.path) { [weak self] in self?.reload() }
        self.layoutWatcher = ConfigWatcher(path: LayoutStore.directory) { [weak self] in self?.reload() }
    }

    /// Construct a host from the current config and mount every widget. Reads `[colors]`
    /// afresh so a config edit to colors/nowplaying takes effect on reload. Called at
    /// launch and again on every reload.
    private func buildSession() {
        // TOML colors override each value from the selected palette file; WIXELS_COLORS
        // replaces only that file selection (see PaletteStore).
        let cfg = Config.load()
        let menuEntries = makeMenuEntries(config: cfg)
        let groupsByIndex = Dictionary(uniqueKeysWithValues: cfg.entries.compactMap { entry in
            let bareKind = Registrar.bareKind(entry.kind)
            let group = entry.folder ?? pluginCatalog.widgets.filter { $0.kind == bareKind }.map(\.group).min()
            return group.map { (entry.sourceIndex, $0) }
        })
        let idsByIndex = Config.stableIDs(entries: cfg.entries, groups: groupsByIndex)
        let services = Services()                                  // shared samplers (cpu, music)
        let host = WidgetHost(
            palette: PaletteStore(colorsPath: cfg.colors.file, overrides: cfg.colors.overrides),
            menuEntries: menuEntries,
            // Suppress the file event our own drag-save write would otherwise raise.
            placementWriter: { [weak self] writes in
                self?.watcher?.ignoringWrites {
                    let scoped = writes.map { write in
                        LayoutWrite(group: write.group, records: write.records,
                                    memberIndexes: Set(groupsByIndex.compactMap { $0.value == write.group ? $0.key : nil }))
                    }
                    self?.layoutWatcher?.ignoringWrites { Config.writeLayouts(scoped) }
                }
            }
        )

        // Mount each entry in file order (order sets z-stacking among same-level
        // widgets — frog before clock).
        for entry in cfg.entries {
            guard entry.enabled else { continue }
            let group = groupsByIndex[entry.sourceIndex]
            guard let group, pluginCatalog.widgets.contains(PluginWidget(group: group, kind: Registrar.bareKind(entry.kind))) else {
                Log.note("no widget for folder '\(entry.folder ?? "(none)")' and kind '\(entry.kind)'")
                continue
            }
            // Per-widget precedence: config `theme` > the folder's bundled theme
            // > global `[theme] default` > macos.
            let themeID = resolvedThemeID(for: entry, group: group, catalog: pluginCatalog,
                                          globalDefault: cfg.theme)
            let layout = idsByIndex[entry.sourceIndex].flatMap { LayoutStore.load(group: group)[$0] }
            if let spec = registrar.specs[entry.kind] {
                let placement = (layout ?? entry.placement).apply(to: spec.defaultPlacement)
                host.mount(spec.build(services, entry.options), placement: placement,
                           defaultPlacement: spec.defaultPlacement, configIndex: entry.sourceIndex,
                           group: group, layoutID: idsByIndex[entry.sourceIndex])
            } else if registrar.themedSpec(for: entry.kind) != nil,
                      let resolved = registrar.resolveThemed(kind: entry.kind,
                          themeID: themeID,
                          services: services, options: entry.options) {
                let placement = (layout ?? entry.placement).apply(to: resolved.placement)
                host.mount(resolved.widget, placement: placement, defaultPlacement: resolved.placement,
                           configIndex: entry.sourceIndex, group: group, layoutID: idsByIndex[entry.sourceIndex])
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
            // Theme resolution is automatic (folder theme > global),
            // so a toggle no longer pins the folder theme onto the row.
            Config.writeWidgetToggle(sourceIndex: info.sourceIndex, kind: info.kind,
                                     folder: info.group, themeID: nil, enabled: on)
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
            Config.writeExclusiveWidgetGroup(selected: selected, configured: configured)
            Config.writeActivePluginFolder(group)
        }
        restart()
    }

    /// After a restart, the selected package's widgets are now available to the
    /// catalog. Enable them before mounting; their bundled theme resolves at mount.
    private func activateSelectedFolderIfNeeded() {
        guard let group = Config.selectedPluginFolder() else { return }
        let infos = makeMenuEntries(config: Config.load())
        let selected = Set(infos.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }.map(\.identity))
        guard !selected.isEmpty else { return }
        let configured = Dictionary(uniqueKeysWithValues: infos.compactMap { info in
            info.sourceIndex.map { ($0, info.identity) }
        })
        Config.writeExclusiveWidgetGroup(selected: selected, configured: configured)
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
