// Registry — the two data structures that decouple widget authoring from layout.
//
//   WidgetSpec  : what a widget IS — its kind, its default placement, and how to
//                 build+mount it. Lives next to the widget (see each Widgets/*.swift
//                 `spec(_:)`), so adding a widget never touches the host.
//   DesktopEntry: what the USER wants — a kind to enable, optionally repositioned.
//                 Lives in Desktop.swift, the one file a user edits.
//
// `associatedtype Sample` blocks `any Widget`, so a spec can't hold a widget
// directly. It holds a `mount` closure that captures the concrete `W` and calls
// the generic `host.mount` — the same erase-at-the-seam move the host already
// uses (Host.swift). main.swift joins the two: for each enabled entry, find its
// spec by kind and mount it with the override placement (or the spec default).

import Foundation

/// What a widget is: its stable kind, where it sits by default, and a closure that
/// constructs the concrete widget and mounts it (capturing its private Sample type).
struct WidgetSpec {
    let kind: String
    let defaultPlacement: Placement
    let mount: @MainActor (WidgetHost, Placement) -> Void
}

/// A user's choice to enable a widget, with an optional placement override.
struct DesktopEntry {
    let kind: String
    let override: Placement?

    /// Enable `kind` at its catalog-default placement, or at `at` to reposition it.
    static func on(_ kind: String, at override: Placement? = nil) -> DesktopEntry {
        DesktopEntry(kind: kind, override: override)
    }
}

/// The one central list of every widget wixels knows how to build. One line per
/// widget, each delegating to that widget's own `spec(_:)`. Adding a widget = add
/// its file (with a `spec`) and one line here; enabling it = a line in Desktop.swift.
@MainActor
func catalog(_ s: Services) -> [WidgetSpec] {
    [
        SysBox.spec(s),
        NowPlaying.spec(s),
        DiskSnail.spec(s),
        CatPet.spec(s),
        Plant.spec(s),
        Quotes.spec(s),
        Frog.spec(s),
        PixelClock.spec(s),
        Stats.spec(s),
        Owl.spec(s),
        Weather.spec(s),
        Poster.spec(s),
    ]
}
