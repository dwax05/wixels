// StatusBar — the menu bar presence. A single NSStatusItem showing "w" that
// proves wixels is alive and lets the user toggle every registered widget.
//
// The menu is rebuilt every time it opens (menuNeedsUpdate) straight from the
// host's current catalog, so checkmarks always reflect the durable config.

import AppKit
import WixelsKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var host: WidgetHost
    private let toggleHandler: (WidgetInfo) -> Void
    private let item: NSStatusItem

    /// Point at the host built by a live config reload. The menu is rebuilt on open
    /// (`menuNeedsUpdate`), so nothing else needs updating and the status item is reused.
    func rebind(host: WidgetHost) { self.host = host }

    init(host: WidgetHost, toggleHandler: @escaping (WidgetInfo) -> Void) {
        self.host = host
        self.toggleHandler = toggleHandler
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "w"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let infos = host.widgetInfos()
        if infos.isEmpty {
            let empty = NSMenuItem(title: "No plugins loaded", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for info in infos {
            let row = NSMenuItem(title: info.label,
                                 action: #selector(toggle(_:)),
                                 keyEquivalent: "")
            row.state = info.enabled ? .on : .off
            row.representedObject = info
            row.target = self
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let openPlugins = NSMenuItem(title: "Open Plugin Folder…",
                                     action: #selector(openPluginFolder(_:)),
                                     keyEquivalent: "")
        openPlugins.target = self
        menu.addItem(openPlugins)
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Layout",
                              action: #selector(toggleEdit(_:)),
                              keyEquivalent: "")
        edit.state = host.editing ? .on : .off
        edit.target = self
        menu.addItem(edit)
        let reset = NSMenuItem(title: "Reset Layout",
                               action: #selector(resetLayout(_:)),
                               keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit wixels",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? WidgetInfo else { return }
        toggleHandler(info)
    }

    @objc private func toggleEdit(_ sender: NSMenuItem) {
        host.setEditMode(!host.editing)
    }

    @objc private func resetLayout(_ sender: NSMenuItem) {
        host.resetLayout()
    }

    @objc private func openPluginFolder(_ sender: NSMenuItem) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/wixels/plugins", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            Log.note("could not open plugin folder: \(error)")
        }
    }
}
