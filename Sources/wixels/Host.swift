// WidgetHost — the deep implementation. Owns everything the widgets don't:
// desktop-level windows, placement, palette injection, and one shared scheduler.
// Delete this and every widget re-grows its own window + timer + palette wiring
// N times over — which is what makes it earn its keep (the deletion test).

import AppKit
import Combine
import SwiftUI

enum Anchor { case topLeft, topRight, bottomLeft, bottomRight, center, topCenter }

/// NSHostingView that accepts the very first click even though the host app is
/// an inactive accessory — otherwise the first tap would just be swallowed.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless NSWindow reports canBecomeKey = false, so it never routes mouse
/// events. A non-activating panel that CAN become key receives clicks without
/// activating the accessory app or stealing focus from the frontmost window —
/// the recipe for a clickable desktop widget.
final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A widget erased to what the host needs: a ticker (refresh its data), placement,
/// size, and a factory for its self-updating SwiftUI view.
private struct Mount {
    let ticker: any WidgetTicker
    let anchor: Anchor
    let offset: CGSize
    let size: CGSize
    let interactive: Bool
    let zBoost: Int          // nudges the window level up so it stacks above peers
    let align: Alignment?    // pins content to a window edge (else NSHostingView centers)
    let makeView: (PaletteStore) -> AnyView
    var window: NSWindow?
}

@MainActor
final class WidgetHost {
    let palette: PaletteStore
    private var mounts: [Mount] = []
    private let scheduler = Scheduler()

    init(palette: PaletteStore = PaletteStore()) { self.palette = palette }

    /// Register a widget. Generic over the concrete `W`, then erased into a Mount.
    @discardableResult
    func mount<W: Widget>(
        _ widget: W, anchor: Anchor, offset: CGSize = .zero,
        size: CGSize = .init(width: 150, height: 70), zBoost: Int = 0, align: Alignment? = nil
    ) -> Self {
        let model = WidgetModel(widget)
        mounts.append(Mount(
            ticker: model,
            anchor: anchor, offset: offset, size: size,
            interactive: W.interactive, zBoost: zBoost, align: align,
            makeView: { AnyView(WidgetView(model: model, palette: $0)) }
        ))
        return self
    }

    /// Placement-struct overload — the form the registry/config path uses. Forwards
    /// to the param mount so both callers share one implementation.
    @discardableResult
    func mount<W: Widget>(_ widget: W, placement p: Placement) -> Self {
        mount(widget, anchor: p.anchor, offset: p.offset, size: p.size,
              zBoost: p.zBoost, align: p.align)
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
            host = ClickableHostingView(rootView: root)
            w = panel
        } else {
            host = NSHostingView(rootView: root)
            w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        }
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
        let vf = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let pad: CGFloat = 20
        let x: CGFloat, y: CGFloat
        switch m.anchor {
        case .topLeft:     x = vf.minX + pad;                y = vf.maxY - m.size.height - pad
        case .topRight:    x = vf.maxX - m.size.width - pad; y = vf.maxY - m.size.height - pad
        case .bottomLeft:  x = vf.minX + pad;                y = vf.minY + pad
        case .bottomRight: x = vf.maxX - m.size.width - pad; y = vf.minY + pad
        case .center:      x = vf.midX - m.size.width / 2;   y = vf.midY - m.size.height / 2
        case .topCenter:   x = vf.midX - m.size.width / 2;   y = vf.maxY - m.size.height - pad
        }
        return NSPoint(x: x + m.offset.width, y: y + m.offset.height)
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
