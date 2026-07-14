// StatusBar — the menu bar presence. A single NSStatusItem showing "w" that
// proves wixels is alive and lets the user toggle each mounted widget on/off.
//
// The menu is rebuilt every time it opens (menuNeedsUpdate) straight from the
// host's current mount list, so checkmarks always reflect live state without
// this controller having to observe the host. Toggles are session-only — they
// override the config while running and reset to the config on next launch.

import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let host: WidgetHost
    private let item: NSStatusItem

    init(host: WidgetHost) {
        self.host = host
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "w"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for info in host.widgetInfos() {
            let row = NSMenuItem(title: info.label,
                                 action: #selector(toggle(_:)),
                                 keyEquivalent: "")
            row.state = info.enabled ? .on : .off
            row.tag = info.index
            row.target = self
            menu.addItem(row)
        }
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
        host.setEnabled(sender.state != .on, at: sender.tag)
    }

    @objc private func toggleEdit(_ sender: NSMenuItem) {
        host.setEditMode(!host.editing)
    }

    @objc private func resetLayout(_ sender: NSMenuItem) {
        host.resetLayout()
    }
}
