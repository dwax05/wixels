// TemplateWidget — a minimal, working example plugin. Copy this package, rename it,
// and edit these two methods. A widget is two things:
//
//   sample()      — fetch the metric (off the main actor). Inject a DataSource from
//                   WixelsKit for anything real (s.cpu, s.music, or your own reader).
//   render(_:_:)  — a PURE function of (Sample, Palette): no state, no I/O. It draws
//                   the widget and recolours whenever the wal palette changes.
//
// `spec()` gives the host the default placement + a `build` closure. `build` receives
// the shared `Services` and this widget's `Options` (from its [widget.options] TOML
// table); ignore either if unused. `erase(_:)` hides the Sample type from the host.
//
// You never touch the host: it supplies the desktop window, palette, scheduler, and
// occlusion pause. Register the widget in Register.swift, `swift build`, and drop the
// dylib in ~/.config/wixels/plugins/.

import SwiftUI
import WixelsKit

struct TemplateWidget: ThemeableWixel {
    static let kind = "template"                       // stable id — used in desktop.toml
    static let refresh: RefreshPolicy = .idleStatic    // or .interval(seconds) to poll

    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .center,
                                    size: .init(width: 150, height: 70)),
            build: { _, _ in TemplateWidget() })
    }

    /// Fetch the metric. Runs off the main actor — do I/O here, never touch the UI.
    func sample() async -> String { "hello" }

    /// Draw it. Pure function of (Sample, Palette) — snapshot-testable, no state.
    func render(_ s: String, _ theme: ThemeContext) -> some View { TemplateView(text: s, theme: theme) }
}

private struct TemplateView: View {
    let text: String
    let theme: ThemeContext
    var body: some View {
        Text(text)
            .font(theme.font(.body))
            .foregroundColor(theme.color(.accent))
            .themedCard(theme)
    }
}
