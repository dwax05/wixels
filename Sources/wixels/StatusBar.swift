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
    private var folders: Set<String>
    private let toggleHandler: (WidgetInfo) -> Void
    private let selectGroupHandler: (String) -> Void
    private let item: NSStatusItem

    /// Point at the host built by a live config reload. The menu is rebuilt on open
    /// (`menuNeedsUpdate`), so nothing else needs updating and the status item is reused.
    func rebind(host: WidgetHost, folders: Set<String>? = nil) {
        self.host = host
        if let folders { self.folders = folders }
    }

    init(host: WidgetHost, folders: Set<String>, toggleHandler: @escaping (WidgetInfo) -> Void,
         selectGroupHandler: @escaping (String) -> Void) {
        self.host = host
        self.folders = folders
        self.toggleHandler = toggleHandler
        self.selectGroupHandler = selectGroupHandler
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
            let empty = NSMenuItem(title: "No widgets installed — install the Cynaberii extension pack, then restart", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        let entriesByGroup = Dictionary(grouping: infos, by: \.group)
        for group in folders.union(entriesByGroup.keys).sorted() {
            let entries = entriesByGroup[group] ?? []
            let folder = NSMenu(title: group)
            let exclusive = NSMenuItem(title: "Enable Only This Folder",
                                       action: #selector(enableOnly(_:)), keyEquivalent: "")
            exclusive.representedObject = group
            exclusive.target = self
            folder.addItem(exclusive)
            if !entries.isEmpty { folder.addItem(.separator()) }
            for info in entries {
                let row = NSMenuItem(title: info.label,
                                     action: #selector(toggle(_:)), keyEquivalent: "")
                row.state = info.enabled ? .on : .off
                row.representedObject = info
                row.target = self
                folder.addItem(row)
            }
            if entries.isEmpty {
                let unavailable = NSMenuItem(title: "Widgets load after switching folders", action: nil, keyEquivalent: "")
                unavailable.isEnabled = false
                folder.addItem(unavailable)
            }
            let folderItem = NSMenuItem(title: group, action: nil, keyEquivalent: "")
            folderItem.submenu = folder
            menu.addItem(folderItem)
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

    @objc private func enableOnly(_ sender: NSMenuItem) {
        guard let group = sender.representedObject as? String else { return }
        selectGroupHandler(group)
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
