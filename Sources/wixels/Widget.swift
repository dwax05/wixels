// Widget — the external seam. A widget author writes the minimum: how to get
// data (`sample`) and how to draw it (`render`). Everything else — window,
// desktop-level pinning, all-Spaces, click-through, palette injection,
// scheduling, occlusion pause — lives behind the host.
//
// Mirrors Übersicht's command/render split: `sample` = command, `render` = render.

import SwiftUI

protocol Widget: Sendable {
    associatedtype Sample: Equatable & Sendable
    associatedtype Content: View
    static var kind: String { get }          // stable id — debug, /tmp force-files
    static var refresh: RefreshPolicy { get }
    static var interactive: Bool { get }     // does the window receive clicks?
    func sample() async -> Sample            // data source            (= command)
    @ViewBuilder func render(_ s: Sample, _ palette: Palette) -> Content   // (= render)
}

extension Widget {
    static var interactive: Bool { false }   // most widgets are click-through wallpaper
}

enum RefreshPolicy: Sendable {
    case interval(TimeInterval)                     // poll (disk, cpu, nowplaying via shared cache)
    case idleStatic                                 // sample once (battery rule)
}

// MARK: - DataSource — internal seam, composed into widgets and injected.

protocol DataSource: Sendable {
    associatedtype Reading: Sendable
    func read() async -> Reading
}

// MARK: - Type erasure at the mount seam.
//
// `associatedtype Sample` blocks `any Widget`. We erase here: the host only ever
// sees `kind`, `refresh`, a `tick()` to refresh data, and a SwiftUI view. The
// widget's `Sample` type stays private, so `render` stays a pure function of
// (Sample, Palette) and remains snapshot-testable.

@MainActor
protocol WidgetTicker: AnyObject {
    var kind: String { get }
    var refresh: RefreshPolicy { get }
    var interactive: Bool { get }
    /// False while the widget's window is fully occluded — the scheduler skips
    /// sampling it then (the battery rule: covered widgets stop sampling).
    var active: Bool { get set }
    func tick() async
}

/// Concrete per-mount model: owns the widget, holds its latest Sample, and
/// produces the view. One of these exists per mounted widget.
@MainActor
final class WidgetModel<W: Widget>: ObservableObject, WidgetTicker {
    let widget: W
    @Published private(set) var sample: W.Sample?
    var active = true      // toggled by the host on window occlusion changes

    init(_ widget: W) { self.widget = widget }

    var kind: String { W.kind }
    var refresh: RefreshPolicy { W.refresh }
    var interactive: Bool { W.interactive }

    func tick() async {
        let s = await widget.sample()
        if s != sample { sample = s }
    }

    @ViewBuilder func view(_ palette: Palette) -> some View {
        if let sample { widget.render(sample, palette) }
        else { Color.clear }   // pre-first-sample
    }
}

/// SwiftUI wrapper that redraws when either the sample or the palette changes.
struct WidgetView<W: Widget>: View {
    @ObservedObject var model: WidgetModel<W>
    @ObservedObject var palette: PaletteStore
    var body: some View { model.view(palette.palette) }
}
