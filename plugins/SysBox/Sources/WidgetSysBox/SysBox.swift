// SysBox — port of cynaberii-sys: a wal-coloured box holding a pixel wifi signal
// and a disk "jar" that fills bottom-up with the Data volume's usage, each under
// a little label. Data from SysSource (CoreWLAN + DiskSource); no shell spawn.
//
// interval(30s): sys.py polled every 60s and nothing animates, so it's ~free once
// drawn. Not interactive — it's a status readout, no click behaviour in the JS.

import SwiftUI
import WixelsKit

struct SysBox: ThemeableWixel {
    let source: SysSource

    static let kind = "sys"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .topLeft, offset: .init(width: 40, height: -60),
                                    size: .init(width: 180, height: 120)),
            build: { _, _ in SysBox(source: SysSource()) })
    }
    static let refresh: RefreshPolicy = .interval(30)
    static let px: CGFloat = 4

    // ascending signal bars (11×7): a=bar1 b=bar2 c=bar3 d=bar4 — all one colour.
    static let wifi: Sprite = [
        ".........d.",
        ".........d.",
        "......c..d.",
        "......c..d.",
        "...b..c..d.",
        "...b..c..d.",
        "a..b..c..d.",
    ]
    // jar outline (10×12): D outline; interior '.' filled bottom-up (m) / empty (n).
    static let jar: Sprite = [
        ".DD....DD.",
        ".DDDDDDDD.",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        "D........D",
        ".DDDDDDDD.",
    ]

    /// Fill the jar interior (rows 2…10) from the bottom by `pct`, mirroring the JS.
    static func jarFilled(_ pct: Double) -> Sprite {
        let interiorRows = 9
        let filled = Int((pct / 100 * Double(interiorRows)).rounded())
        return jar.enumerated().map { r, line in
            guard (2...10).contains(r) else { return line }
            let fromBottom = 10 - r                         // 0 at bottom row (r=10)
            let ch: Character = fromBottom < filled ? "m" : "n"
            return String(line.map { $0 == "." ? ch : $0 })
        }
    }

    func sample() async -> SysInfo { await source.read() }

    func render(_ s: SysInfo, _ theme: ThemeContext) -> some View { SysView(info: s, theme: theme) }
}

private struct SysView: View {
    let info: SysInfo
    let theme: ThemeContext

    var body: some View {
        let on = theme.color(info.connected ? .accent : .muted)
        let ink = theme.color(.foreground)
        let sage = theme.color(.secondary)
        let jarPal: [Character: Color] = [
            "D": theme.color(.alternateAccent),
            "m": sage,                  // filled
            "n": theme.color(.muted),
        ]

        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 6) {
                PixelStrip(frames: [SysBox.wifi], px: SysBox.px,
                           palette: ["a": on, "b": on, "c": on, "d": on])
                    .frame(height: 12 * SysBox.px, alignment: .bottom)   // baseline-align bars
                label("wifi", info.connected ? "on" : "off", on, ink)
            }
            VStack(spacing: 6) {
                PixelStrip(frames: [SysBox.jarFilled(info.diskPct)], px: SysBox.px, palette: jarPal)
                label("disk", "\(Int(info.diskPct.rounded()))%", sage, ink)
            }
        }
        .themedCard(theme, insets: .init(top: 14, leading: 18, bottom: 14, trailing: 18))
    }

    private func label(_ t: String, _ v: String, _ tColor: Color, _ ink: Color) -> some View {
        (Text(t + " ").foregroundColor(tColor) + Text(v).foregroundColor(ink))
            .font(theme.font(.label))
    }
}
