// Stats — port of cynaberii-stats: real pixel art on a card pane.
//   plant → CPU load  (4 wilt frames; pot face smiles → frowns)
//   soil  → memory used (sage water level in the pot)
//   heart → battery %  (fills bottom-up; blush cheeks when charging/plugged)
// Native StatsSource (host ticks, host_statistics64, IOPS) — no tool spawns.

import SwiftUI
import WixelsKit

struct Stats: ThemeableWixel {
    let source: StatsSource

    static let kind = "stats"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomRight, offset: .init(width: 0, height: 36),
                                    size: .init(width: 220, height: 164), align: .trailing, sizing: .fitContent),
            build: { s, _ in Stats(source: StatsSource(cpu: s.cpu)) })
    }
    static let refresh: RefreshPolicy = .interval(20)
    static let px: CGFloat = 6

    // leaf frames by wilt stage (9 wide). l leaf · s stem
    static let leaves: [Sprite] = [
        ["..l...l..", ".lll.lll.", ".lll.lll.", "..l.s.l..", "....s....", "...lsl...", "....s...."],
        [".........", "..l...l..", ".lll.lll.", ".lls.sll.", "....s....", "...lsl...", "....s...."],
        [".........", ".........", ".l.....l.", "lll.s.lll", ".ll.s.ll.", "...lsl...", "....s...."],
        [".........", ".........", ".........", "....s....", ".ll.s.ll.", "lll.s.lll", ".l.lsl.l."],
    ]
    // pot base (9 wide); soil rows (idx 1,2) + face cells filled in below
    static let pot: Sprite = [
        "rrrrrrrrr", "sssssssss", "sssssssss", "ppppppppp",
        "ppppppppp", "ppppppppp", "ppppppppp", ".ppppppp.",
    ]
    static let eyes: [Cell] = [(4, 2, "e"), (4, 6, "e")]
    static let mouths: [Int: [Cell]] = [
        0: [(6, 2, "e"), (6, 6, "e"), (7, 3, "e"), (7, 4, "e"), (7, 5, "e")],   // happy
        1: [(7, 2, "e"), (7, 3, "e"), (7, 4, "e"), (7, 5, "e"), (7, 6, "e")],   // flat
        2: [(6, 3, "e"), (6, 4, "e"), (6, 5, "e"), (7, 2, "e"), (7, 6, "e")],   // sad
    ]

    static let heart: Sprite = [
        ".HH.HH.", "HHHHHHH", "HHHHHHH", "HHHHHHH", ".HHHHH.", "..HHH..", "...H...",
    ]

    /// Leaf frame + pot with the soil level (memory) and face (wilt) baked in.
    static func plant(wilt: Int, mem: Int) -> Sprite {
        let soilRows = Int((Double(mem) / 100 * 2).rounded())   // 0…2 filled
        var pot = self.pot.enumerated().map { r, row -> String in
            if r == 1 { return String(repeating: soilRows >= 2 ? "m" : "d", count: 9) }
            if r == 2 { return String(repeating: soilRows >= 1 ? "m" : "d", count: 9) }
            return row
        }
        let mouth = mouths[min(2, wilt <= 1 ? 0 : wilt - 1)] ?? mouths[0]!
        pot = set(pot, eyes + mouth)
        return leaves[wilt] + pot
    }

    /// Heart filled bottom-up by battery %, optional blush cheeks.
    static func heart(pct: Int, blush: Bool) -> Sprite {
        let filled = Int((Double(pct) / 100 * Double(heart.count)).rounded())
        var rows = heart.enumerated().map { r, line in
            String(line.map { $0 == "H" ? (r >= heart.count - filled ? "F" : "E") : "." })
        }
        if blush { rows = set(rows, [(2, 1, "b"), (2, 5, "b")]) }
        return rows
    }

    func sample() async -> StatsInfo { await source.read() }
    func render(_ sample: StatsInfo, _ theme: ThemeContext) -> some View { StatsView(s: sample, theme: theme) }
}

struct StatsView: View {
    let s: StatsInfo
    let theme: ThemeContext

    var body: some View {
        let ink = theme.color(.foreground)
        let wilt = s.cpu < 25 ? 0 : s.cpu < 50 ? 1 : s.cpu < 75 ? 2 : 3
        let leaf = [theme.color(.positive), theme.color(.secondary), theme.color(.warning), theme.color(.negative)][wilt]
        let plantPal: [Character: Color] = [
            "l": leaf, "s": leaf,
            "r": theme.color(.accent), "p": theme.color(.alternateAccent),
            "m": theme.color(.secondary), "d": theme.color(.muted),
            "e": theme.color(.background),
        ]
        let blush = s.charging || s.plugged
        let heartPal: [Character: Color] = [
            "F": theme.color(s.charging ? .positive : .accent),
            "E": theme.color(.muted), "b": theme.color(.alternateAccent),
        ]
        let spriteH = 15 * Stats.px      // plant is the tallest sprite

        return HStack(alignment: .bottom, spacing: 20) {
            VStack(spacing: 6) {
                bottomBox(spriteH) {
                    PixelStrip(frames: [Stats.plant(wilt: wilt, mem: s.mem)], px: Stats.px, palette: plantPal)
                }
                label("cpu", s.cpu, leaf, ink)
                label("mem", s.mem, theme.color(.secondary), ink)
            }
            VStack(spacing: 6) {
                bottomBox(spriteH) {
                    PixelStrip(frames: [Stats.heart(pct: s.battery, blush: blush)], px: Stats.px, palette: heartPal)
                }
                label("batt", s.battery, theme.color(.accent), ink)
            }
        }
        .fixedSize()   // hug the sprites; don't stretch to the window
        .themedCard(theme, insets: .init(top: 14, leading: 18, bottom: 14, trailing: 18))
    }

    private func bottomBox<V: View>(_ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content().frame(height: h, alignment: .bottom)
    }

    private func label(_ t: String, _ v: Int, _ tColor: Color, _ ink: Color) -> some View {
        (Text(t + " ").foregroundColor(tColor) + Text("\(v)%").foregroundColor(ink))
            .font(theme.font(.label))
    }
}
