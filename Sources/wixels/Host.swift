// WidgetHost — the deep implementation. Owns everything the widgets don't:
// desktop-level windows, placement, palette injection, and one shared scheduler.
// Delete this and every widget re-grows its own window + timer + palette wiring
// N times over — which is what makes it earn its keep (the deletion test).

import AppKit
import Combine
import SwiftUI
import WixelsKit

/// The SwiftUI content fills the whole window, so AppKit's
/// `isMovableByWindowBackground` never gets a background click to drag. This view
/// owns the explicit layout-mode drag instead, while preserving normal widget
/// interaction outside edit mode.
final class LayoutHostingView<Content: View>: NSHostingView<Content> {
    var layoutEditing = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if layoutEditing {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// A borderless NSWindow reports canBecomeKey = false, so it never routes mouse
/// events. A non-activating panel that CAN become key receives clicks without
/// activating the accessory app or stealing focus from the frontmost window —
/// the recipe for a clickable desktop widget.
final class DesktopWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Desktop panels may intentionally sit inside AppKit's edge-avoidance area.
    /// Keep their requested plugin frame when they are ordered onscreen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// A widget erased to what the host needs: a ticker (refresh its data), placement,
/// size, and a factory for its self-updating SwiftUI view.
private struct Mount {
    let ticker: any WidgetTicker
    var anchor: WixelsKit.Anchor
    var offset: CGSize       // var: edit mode rewrites it on drop
    let defaultPlacement: Placement
    let size: CGSize
    let interactive: Bool
    let zBoost: Int          // nudges the window level up so it stacks above peers
    let align: Alignment?    // pins content to a window edge (else NSHostingView centers)
    let kind: String
    let configIndex: Int     // index into the config's [[widget]] blocks (for write-back)
    let makeView: (PaletteStore) -> AnyView
    var window: NSWindow?
    var enabled: Bool = true   // false = user turned it off from the menu bar
    // Saved window state while in edit mode, restored on exit.
    var savedAnchor: WixelsKit.Anchor?
    var savedOffset: CGSize?
    var savedFrameOrigin: NSPoint?
    var savedLevel: NSWindow.Level?
    var savedIgnoresMouse: Bool?
}

/// A menu-bar-facing summary of one mounted widget: enough to draw a checkmark
/// row and route a toggle back by index. `label` disambiguates duplicate kinds.
struct WidgetInfo { let index: Int; let kind: String; let label: String; let enabled: Bool }

struct LayoutSnapshot: Equatable {
    let configIndex: Int
    let kind: String
    let interactive: Bool
    let frame: NSRect
}

@MainActor
final class WidgetHost {
    let palette: PaletteStore
    private var mounts: [Mount] = []
    private let scheduler = Scheduler()
    private let placementWriter: ([PlacementChange]) -> Void
    /// Freeze the coordinate system for this host lifetime. AppKit can change which
    /// screen is `main` while edit mode activates the accessory app; using that live
    /// value to recover offsets made untouched widgets drift into the config.
    private let layoutFrame: NSRect

    init(palette: PaletteStore = PaletteStore(),
         placementWriter: @escaping ([PlacementChange]) -> Void = Config.writePlacements) {
        self.palette = palette
        self.placementWriter = placementWriter
        self.layoutFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Mount an already-erased widget (from a plugin spec's `build`) at a placement.
    /// The ticker and the view come from the same `MountableWidget`, so they share
    /// one model — a scheduler tick republishes exactly what the view observes.
    @discardableResult
    func mount(_ widget: any MountableWidget, placement p: Placement,
               defaultPlacement: Placement, configIndex: Int) -> Self {
        mounts.append(Mount(
            ticker: widget.makeTicker(),
            anchor: p.anchor, offset: p.offset,
            defaultPlacement: defaultPlacement,
            size: p.size,
            interactive: widget.interactive, zBoost: p.zBoost, align: p.align,
            kind: widget.kind, configIndex: configIndex,
            makeView: { widget.makeView($0) }
        ))
        return self
    }

    /// The mounted widgets in menu order, each labelled for display. Duplicate
    /// kinds get a `#2`, `#3` suffix so the menu can tell two clocks apart.
    func widgetInfos() -> [WidgetInfo] {
        var seen: [String: Int] = [:]
        return mounts.indices.map { i in
            let kind = mounts[i].kind
            let n = (seen[kind] ?? 0) + 1
            seen[kind] = n
            let label = n == 1 ? kind : "\(kind) #\(n)"
            return WidgetInfo(index: i, kind: kind, label: label, enabled: mounts[i].enabled)
        }
    }

    func layoutSnapshot() -> [LayoutSnapshot] {
        mounts.compactMap { mount in
            mount.window.map {
                LayoutSnapshot(configIndex: mount.configIndex, kind: mount.kind,
                               interactive: mount.interactive, frame: $0.frame)
            }
        }
    }

    /// Turn a widget on/off from the menu bar. Off = hide the window and gate its
    /// ticker so the scheduler stops sampling it; on = reveal it and catch its
    /// sample up (mirrors the occlusion re-arm). Session-only — no config write.
    func setEnabled(_ on: Bool, at index: Int) {
        guard mounts.indices.contains(index) else { return }
        mounts[index].enabled = on
        let ticker = mounts[index].ticker
        if on {
            mounts[index].window?.orderFront(nil)
            ticker.active = true
            Task { await ticker.tick() }
        } else {
            mounts[index].window?.orderOut(nil)
            ticker.active = false
        }
    }

    /// Whether the user has entered layout-edit mode from the menu bar.
    private(set) var editing = false
    private var movedConfigIndexes: Set<Int> = []
    private var editKeyMonitor: Any?    // local keyDown monitor (Enter=save, Esc=discard)
    private var editKeyWindow: NSPanel? // ephemeral key panel so the app receives keys
    private var editMoveObserver: (any NSObjectProtocol)?

    /// Enter drag-to-reposition mode. Brings every widget forward, makes it draggable by
    /// its background, and outlines it so transparent widgets are grabbable. Exit via
    /// `endEditMode` — Enter/Escape while editing route here (save / discard).
    func setEditMode(_ on: Bool) {
        if on { beginEditMode() } else { endEditMode(save: true) }
    }

    /// Reset every widget directly from the menu bar. Leave edit mode without
    /// saving first so this path does not recover offsets from floating windows.
    func resetLayout() {
        if editing { endEditMode(save: false) }

        var changes: [PlacementChange] = []
        for i in mounts.indices {
            let defaults = mounts[i].defaultPlacement
            guard mounts[i].anchor != defaults.anchor || mounts[i].offset != defaults.offset else {
                continue
            }
            mounts[i].anchor = defaults.anchor
            mounts[i].offset = defaults.offset
            mounts[i].window?.setFrameOrigin(origin(for: mounts[i]))
            changes.append(.init(configIndex: mounts[i].configIndex,
                                 anchor: mounts[i].anchor,
                                 offset: mounts[i].offset))
        }
        placementWriter(changes)
    }

    private func beginEditMode() {
        guard !editing else { return }
        editing = true
        movedConfigIndexes.removeAll()
        for i in mounts.indices {
            mounts[i].savedAnchor = mounts[i].anchor
            mounts[i].savedOffset = mounts[i].offset
            enterEdit(&mounts[i])
        }
        installEditKeyCapture()
    }

    /// Leave edit mode. `save` writes moved offsets to the config; otherwise every widget
    /// snaps back to its pre-edit position and nothing is written.
    func endEditMode(save: Bool) {
        guard editing else { return }
        editing = false
        removeEditKeyCapture()
        if save {
            var changes: [PlacementChange] = []
            for i in mounts.indices {
                let persistMove = movedConfigIndexes.contains(mounts[i].configIndex)
                if let off = exitEdit(&mounts[i], save: true, commitOffset: persistMove) {
                    changes.append(.init(configIndex: mounts[i].configIndex, anchor: nil, offset: off))
                }
            }
            if !changes.isEmpty { placementWriter(changes) }
        } else {
            for i in mounts.indices { _ = exitEdit(&mounts[i], save: false) }
        }
        movedConfigIndexes.removeAll()
    }

    /// A hidden non-activating key panel lets this accessory app receive keyDown without
    /// stealing focus; a local monitor turns Enter into save-and-exit, Escape into discard.
    private func installEditKeyCapture() {
        // Activate the (accessory) app and give it a key window so keyDown routes here.
        NSApp.activate(ignoringOtherApps: true)
        let vf = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 100, height: 100)
        let panel = InteractivePanel(contentRect: .init(x: vf.minX, y: vf.minY, width: 1, height: 1),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.alphaValue = 0.01
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.makeKeyAndOrderFront(nil)
        editKeyWindow = panel
        editMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, self.editing,
                      let window,
                      let mount = self.mounts.first(where: { $0.window === window }) else { return }
                self.movedConfigIndexes.insert(mount.configIndex)
            }
        }
        editKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.editing else { return e }
            switch e.keyCode {
            case 36, 76: self.endEditMode(save: true);  return nil   // Return / keypad Enter
            case 53:     self.endEditMode(save: false); return nil   // Escape
            default:     return e
            }
        }
    }

    private func removeEditKeyCapture() {
        if let m = editKeyMonitor { NSEvent.removeMonitor(m); editKeyMonitor = nil }
        if let o = editMoveObserver { NotificationCenter.default.removeObserver(o); editMoveObserver = nil }
        editKeyWindow?.orderOut(nil); editKeyWindow = nil
    }

    private func enterEdit(_ m: inout Mount) {
        guard m.enabled, let w = m.window else { return }
        m.savedFrameOrigin = w.frame.origin
        m.savedLevel = w.level
        m.savedIgnoresMouse = w.ignoresMouseEvents
        w.ignoresMouseEvents = false
        (w.contentView as? LayoutHostingView<AnyView>)?.layoutEditing = true
        w.level = .floating           // come forward so desktop-level widgets are clickable
        if let host = w.contentView {
            let c = palette.palette.c(1)   // an accent — reads against any theme
            let (r, g, b) = (c.r / 255, c.g / 255, c.b / 255)
            host.wantsLayer = true
            host.layer?.borderWidth = 1
            host.layer?.borderColor = CGColor(red: r, green: g, blue: b, alpha: 0.9)
            host.layer?.backgroundColor = CGColor(red: r, green: g, blue: b, alpha: 0.12)
        }
        w.orderFront(nil)
    }

    /// Restore the window chrome/level. When `save`, return the widget's new offset if it
    /// moved; when discarding, snap the window back to its pre-edit position and return nil.
    @discardableResult
    private func exitEdit(_ m: inout Mount, save: Bool, commitOffset: Bool = true) -> CGSize? {
        if !save {
            if let anchor = m.savedAnchor { m.anchor = anchor }
            if let offset = m.savedOffset { m.offset = offset }
        }
        guard let w = m.window else {
            m.savedAnchor = nil; m.savedOffset = nil; m.savedFrameOrigin = nil
            return nil
        }
        let base = anchoredBase(anchor: m.anchor, size: m.size)
        let o = w.frame.origin
        let newOffset = CGSize(width: (o.x - base.x).rounded(), height: (o.y - base.y).rounded())

        (w.contentView as? LayoutHostingView<AnyView>)?.layoutEditing = false
        if let lvl = m.savedLevel { w.level = lvl }
        if let ig = m.savedIgnoresMouse { w.ignoresMouseEvents = ig }
        m.savedLevel = nil; m.savedIgnoresMouse = nil
        if let host = w.contentView {
            host.layer?.borderWidth = 0
            host.layer?.backgroundColor = nil
        }

        if !save {
            if let origin = m.savedFrameOrigin { w.setFrameOrigin(origin) }
            m.savedAnchor = nil; m.savedOffset = nil; m.savedFrameOrigin = nil
            if m.enabled { w.orderFront(nil) }
            return nil
        }
        m.savedAnchor = nil; m.savedOffset = nil; m.savedFrameOrigin = nil
        if m.enabled { w.orderFront(nil) }
        guard commitOffset, newOffset != m.offset else { return nil }
        m.offset = newOffset
        return newOffset
    }

    private var occlusionObserver: (any NSObjectProtocol)?
    private var paletteObserver: AnyCancellable?

    func run() {
        for i in mounts.indices {
            let w = makeWindow(mounts[i])
            mounts[i].window = w
            scheduler.add(mounts[i].ticker)
        }
        observeOcclusion()
        observePalette()
        scheduler.start()
        print("wixels up — \(mounts.count) widget(s). Try `wal -R` to recolour. Ctrl-C to quit.")
    }

    /// idleStatic widgets sample once at launch and then only on a palette change
    /// (the battery rule: no polling). Re-tick them when wal recolours so any that
    /// derive data from the theme, or want a fresh reading on theme switch, refresh.
    private func observePalette() {
        paletteObserver = palette.$reloadCount
            .dropFirst()
            .sink { [weak self] _ in self?.scheduler.refreshOnce() }
    }

    /// Occlusion-aware pause: when a widget's window is fully covered, gate its
    /// ticker off so the scheduler stops sampling it (SwiftUI already halts the
    /// TimelineView animation for a non-visible window). Uncovering re-arms it.
    private func observeOcclusion() {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let win = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let win,
                      let i = self.mounts.firstIndex(where: { $0.window === win }) else { return }
                // A user-disabled widget stays off — don't let occlusion re-arm it.
                guard self.mounts[i].enabled else { return }
                let ticker = self.mounts[i].ticker
                let visible = win.occlusionState.contains(.visible)
                let wasActive = ticker.active
                ticker.active = visible
                // Uncovering: catch up immediately so the widget isn't showing a
                // stale sample (or, for push widgets, a missed event) until its
                // next scheduled tick.
                if visible && !wasActive { Task { await ticker.tick() } }
            }
        }
    }

    private func makeWindow(_ m: Mount) -> NSWindow {
        let frame = NSRect(origin: .zero, size: m.size)
        // align pins the content to a window edge (else NSHostingView centers it,
        // which lets equal-anchored cards land at different edges by window width).
        let base = m.makeView(palette)
        let root: AnyView = m.align.map {
            AnyView(base.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: $0))
        } ?? base
        let w: NSWindow
        let host: NSHostingView<AnyView>
        if m.interactive {
            // non-activating panel so clicks land without focus theft
            let panel = InteractivePanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            host = LayoutHostingView(rootView: root)
            w = panel
        } else {
            host = LayoutHostingView(rootView: root)
            w = DesktopWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        }
        // Placement sizes are authoritative. NSHostingView otherwise publishes its
        // SwiftUI intrinsic size back to AppKit after the window is shown, shrinking
        // the frame while preserving its top edge. A later reset then anchors using
        // the declared size and appears to push only the shrunken widgets downward.
        host.sizingOptions = []
        host.frame = frame
        w.contentView = host
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = !m.interactive             // click-through unless interactive
        // .desktopWindow sits BELOW where WindowServer routes clicks (Finder eats
        // them), so an interactive widget there never sees a mouse event. Desktop
        // icons live one level up and ARE clickable — put interactive panels there.
        let levelKey: CGWindowLevelKey = m.interactive ? .desktopIconWindow : .desktopWindow
        // zBoost keeps a widget above its peers even after a click reorders windows
        // within a level (e.g. the clock staying above the frog it hides).
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(levelKey)) + m.zBoost)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.setFrameOrigin(origin(for: m))
        w.orderFront(nil)
        return w
    }

    private func origin(for m: Mount) -> NSPoint {
        let base = anchoredBase(anchor: m.anchor, size: m.size)
        return NSPoint(x: base.x + m.offset.width, y: base.y + m.offset.height)
    }

    /// The zero-offset window origin for an anchor+size in the host's fixed screen
    /// frame. Placement adds the widget's offset to this; edit mode subtracts it back
    /// out of a dropped frame to recover the offset.
    private func anchoredBase(anchor: WixelsKit.Anchor, size: CGSize) -> NSPoint {
        let vf = layoutFrame
        let pad: CGFloat = 20
        let x: CGFloat, y: CGFloat
        switch anchor {
        case .topLeft:     x = vf.minX + pad;              y = vf.maxY - size.height - pad
        case .topRight:    x = vf.maxX - size.width - pad; y = vf.maxY - size.height - pad
        case .bottomLeft:  x = vf.minX + pad;              y = vf.minY + pad
        case .bottomRight: x = vf.maxX - size.width - pad; y = vf.minY + pad
        case .center:      x = vf.midX - size.width / 2;   y = vf.midY - size.height / 2
        case .topCenter:   x = vf.midX - size.width / 2;   y = vf.maxY - size.height - pad
        }
        return NSPoint(x: x, y: y)
    }
}

/// One shared scheduler for every widget — not N timers. `.interval` widgets are
/// coalesced onto a single 1s base loop that ticks each when its period elapses;
/// `.idleStatic` ticks once.
@MainActor
final class Scheduler {
    private struct Periodic { let ticker: any WidgetTicker; let period: TimeInterval; var last: Date }
    private var periodics: [Periodic] = []
    private var once: [any WidgetTicker] = []
    private var loop: Task<Void, Never>?

    func add(_ t: any WidgetTicker) {
        switch t.refresh {
        case .interval(let p): periodics.append(.init(ticker: t, period: p, last: .distantPast))
        case .idleStatic:      once.append(t)
        }
    }

    /// Re-tick every idleStatic widget — driven by the host on a palette change,
    /// the one refresh trigger idleStatic widgets get after their launch sample.
    func refreshOnce() {
        for t in once where t.active { Task { await t.tick() } }
    }

    func start() {
        for t in once { Task { await t.tick() } }
        guard !periodics.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                guard let self else { return }
                for i in self.periodics.indices where
                    self.periodics[i].ticker.active &&
                    now.timeIntervalSince(self.periodics[i].last) >= self.periodics[i].period {
                    self.periodics[i].last = now
                    await self.periodics[i].ticker.tick()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    deinit { loop?.cancel() }
}
