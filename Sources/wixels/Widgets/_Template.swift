// _Template — copy this file to author a new widget. Four steps to a live widget:
//
//   1. Copy this file to Widgets/MyThing.swift and rename `TemplateWidget`.
//   2. Fill in `sample()` (fetch data — inject a DataSource for anything real, see
//      Sources.swift) and `render(_:_:)` (a pure function of Sample + Palette).
//   3. Add `MyThing.spec(s)` to `catalog(_:)` in Registry.swift.
//   4. Enable it with `.on("my-kind")` in Desktop.swift.
//
// No edits to main.swift or Host.swift ever needed. The host supplies the window,
// desktop pinning, palette, scheduler, and occlusion pause — you write only the two
// methods plus the spec. Delete this file if you don't want it in your build.

import SwiftUI
import WixelsKit

struct TemplateWidget: Wixel {
    static let kind = "template"                       // stable id, referenced in Desktop.swift
    static let refresh: RefreshPolicy = .idleStatic    // or .interval(seconds) to poll

    /// Default placement + how to build this widget. `build` gets the shared
    /// samplers (s.cpu, s.music) and this widget's `Options` from the config; ignore
    /// either if unused. `erase(_:)` hides the widget's Sample type from the host.
    static func spec() -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .center,
                                    size: .init(width: 150, height: 70)),
            build: { _, _ in erase(TemplateWidget()) })
    }

    /// Fetch the metric. Runs off the main actor; do the I/O here, no UI.
    func sample() async -> String { "hello" }

    /// Draw it. Pure function of (Sample, Palette) — snapshot-testable, no state.
    /// Hand off to a child View so SwiftUI modifiers run in their View context.
    func render(_ s: String, _ p: Palette) -> some View { TemplateView(text: s, p: p) }
}

private struct TemplateView: View {
    let text: String
    let p: Palette
    var body: some View {
        Text(text)
            .font(.pixel(12))
            .foregroundColor(p.c(4).color)
            .pane(p)
    }
}
