// Catalog — TRANSITIONAL: the built-in widgets still linked into the host, listed
// statically. Phase 2 moved clock + stats out to real plugin dylibs (loaded by
// PluginLoader), so they're gone from here. Phase 4 empties this entirely and every
// widget arrives via plugin registration.
//
// DesktopEntry stays host-side (config concern); the reusable spec/registry types
// moved to WixelsKit.

import WixelsKit

/// A user's choice to enable a widget, with an optional placement override.
struct DesktopEntry {
    let kind: String
    let override: Placement?

    /// Enable `kind` at its catalog-default placement, or at `at` to reposition it.
    static func on(_ kind: String, at override: Placement? = nil) -> DesktopEntry {
        DesktopEntry(kind: kind, override: override)
    }
}

/// Every built-in widget's spec. One line each, delegating to the widget's own
/// `spec()`. (Phase 4: replaced by plugin registration.)
@MainActor
func catalog() -> [WidgetSpec] {
    [
        SysBox.spec(),
        NowPlaying.spec(),
        DiskSnail.spec(),
        CatPet.spec(),
        Plant.spec(),
        Quotes.spec(),
        Frog.spec(),
        // clock + stats now load as plugins (WidgetClock / WidgetStats dylibs)
        Owl.spec(),
        Weather.spec(),
        Poster.spec(),
    ]
}
