// Widget — the external seam a plugin author implements: registration (`spec`),
// data acquisition (`sample`), and view construction (`render`). Everything else — window,
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
    static func spec() -> WidgetSpec         // registration + placement + construction
    func sample() async -> Sample            // data source            (= command)
    @MainActor @ViewBuilder func render(_ s: Sample, _ palette: Palette) -> Content   // (= render)
}

public extension Wixel {
    static var interactive: Bool { false }   // most widgets are click-through wallpaper
}

public protocol ThemeableWixel: Sendable {
    associatedtype Sample: Equatable & Sendable
    associatedtype Content: View
    static var kind: String { get }
    static var refresh: RefreshPolicy { get }
    static var interactive: Bool { get }
    static func spec() -> ThemedWidgetSpec
    func sample() async -> Sample
    @MainActor @ViewBuilder func render(_ sample: Sample, _ theme: ThemeContext) -> Content
}

public extension ThemeableWixel {
    static var interactive: Bool { false }
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
// view bound to that same model. The `Sample` type stays private. Passive widgets
// can render deterministically from (Sample, Palette); interactive views may own
// local UI state or invoke explicit user actions after construction.

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
func eraseThemed<W: ThemeableWixel>(_ widget: W, theme: ThemeDefinition)
    -> any MountableWidget { ErasedThemedWidget(widget, theme: theme) }

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

@MainActor
final class ErasedThemedWidget<W: ThemeableWixel>: MountableWidget {
    private let model: ThemedWidgetModel<W>
    init(_ widget: W, theme: ThemeDefinition) { model = ThemedWidgetModel(widget, theme: theme) }
    var kind: String { W.kind }
    var refresh: RefreshPolicy { W.refresh }
    var interactive: Bool { W.interactive }
    func makeTicker() -> any WidgetTicker { model }
    func makeView(_ palette: PaletteStore) -> AnyView { AnyView(ThemedWidgetView(model: model, palette: palette)) }
}

@MainActor
final class ThemedWidgetModel<W: ThemeableWixel>: ObservableObject, WidgetTicker {
    let widget: W
    let theme: ThemeDefinition
    @Published private(set) var sample: W.Sample?
    var active = true
    init(_ widget: W, theme: ThemeDefinition) { self.widget = widget; self.theme = theme }
    var kind: String { W.kind }
    var refresh: RefreshPolicy { W.refresh }
    var interactive: Bool { W.interactive }
    func tick() async { let next = await widget.sample(); if next != sample { sample = next } }
    func view(_ palette: Palette) -> AnyView {
        guard let sample else { return AnyView(Color.clear) }
        return AnyView(widget.render(sample, ThemeContext(definition: theme,
            palette: palette)))
    }
}

struct ThemedWidgetView<W: ThemeableWixel>: View {
    @ObservedObject var model: ThemedWidgetModel<W>
    @ObservedObject var palette: PaletteStore
    var body: some View { model.view(palette.resolvedPalette(for: model.theme)) }
}
