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

struct TemplateWidget: Widget {
    static let kind = "template"                       // stable id, referenced in Desktop.swift
    static let refresh: RefreshPolicy = .idleStatic    // or .interval(seconds) to poll

    /// Default placement + how to build this widget. `s: Services` gives you the
    /// shared samplers (s.cpu, s.music) if you need them; ignore it otherwise.
    static func spec(_ s: Services) -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .center,
                                    size: .init(width: 150, height: 70)),
            mount: { host, p in host.mount(TemplateWidget(), placement: p) })
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
