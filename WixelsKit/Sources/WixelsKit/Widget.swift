// Widget — the external seam a plugin author implements. Two methods: how to get
// data (`sample`) and how to draw it (`render`). Everything else — window,
// desktop pinning, scheduling, occlusion pause — lives behind the host.
//
// This is the plugin ABI, so the shared contracts are `public`. A plugin links
// WixelsKit (the one dynamic copy, so type identity holds across dlopen), builds
// its widget, and hands the host an erased `any MountableWidget` — the host never
// sees the widget's private `Sample` type, and never needs to be visible to the
// plugin.

import SwiftUI

public protocol Wixel: Sendable {
    associatedtype Sample: Equatable & Sendable
    associatedtype Content: View
    static var kind: String { get }          // stable id — config + debug
    static var refresh: RefreshPolicy { get }
    static var interactive: Bool { get }     // does the window receive clicks?
    func sample() async -> Sample            // data source            (= command)
    @MainActor @ViewBuilder func render(_ s: Sample, _ palette: Palette) -> Content   // (= render)
}

public extension Wixel {
    static var interactive: Bool { false }   // most widgets are click-through wallpaper
}

public enum RefreshPolicy: Sendable {
    case interval(TimeInterval)                     // poll (disk, cpu, nowplaying via shared cache)
    case idleStatic                                 // sample once (battery rule)
}

// MARK: - DataSource — internal seam, composed into widgets and injected.

public protocol DataSource: Sendable {
    associatedtype Reading: Sendable
    func read() async -> Reading
}

// MARK: - The host-facing erased interface.
//
// `associatedtype Sample` blocks `any Widget`. A widget is erased to what the host
// needs: `kind`/`refresh`/`interactive`, a `tick()`-able data model, and a SwiftUI
// view bound to that same model. The `Sample` type stays private, so `render` stays
// a pure function of (Sample, Palette) and remains snapshot-testable.

@MainActor
public protocol WidgetTicker: AnyObject {
    var kind: String { get }
    var refresh: RefreshPolicy { get }
    var interactive: Bool { get }
    /// False while the widget's window is fully occluded — the scheduler skips
    /// sampling it then (the battery rule: covered widgets stop sampling).
    var active: Bool { get set }
    func tick() async
}

/// A widget erased for the host: its ticker and its view share one model instance,
/// so a scheduler tick republishes the sample the view is observing. `erase(_:)`
/// below is the only way to make one.
@MainActor
public protocol MountableWidget {
    var kind: String { get }
    var refresh: RefreshPolicy { get }
    var interactive: Bool { get }
    func makeTicker() -> any WidgetTicker
    func makeView(_ palette: PaletteStore) -> AnyView
}

/// Erase a concrete widget. Builds the one shared `WidgetModel` and exposes it as
/// both ticker (for the scheduler) and view (for the window).
@MainActor
public func erase<W: Wixel>(_ widget: W) -> any MountableWidget { ErasedWidget(widget) }

@MainActor
final class ErasedWidget<W: Wixel>: MountableWidget {
    private let model: WidgetModel<W>
    init(_ widget: W) { model = WidgetModel(widget) }
    var kind: String { W.kind }
    var refresh: RefreshPolicy { W.refresh }
    var interactive: Bool { W.interactive }
    func makeTicker() -> any WidgetTicker { model }
    func makeView(_ palette: PaletteStore) -> AnyView {
        AnyView(WidgetView(model: model, palette: palette))
    }
}

/// Concrete per-mount model: owns the widget, holds its latest Sample, and produces
/// the view. One of these exists per mounted widget. Internal — only `erase` makes them.
@MainActor
final class WidgetModel<W: Wixel>: ObservableObject, WidgetTicker {
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
struct WidgetView<W: Wixel>: View {
    @ObservedObject var model: WidgetModel<W>
    @ObservedObject var palette: PaletteStore
    var body: some View { model.view(palette.palette) }
}
