// Owl — port of cynaberii-owl: a pixel owl perched above the stats card, acting as
// a presence gauge from your idle time (OwlSource / HID idle):
//   awake  → eyes wide open      drowsy → eyes half-lidded
//   asleep → eyes shut + floating "z"s
// Click makes it blink. Loose transparent sprite (no pane).

import SwiftUI
import WixelsKit

struct Owl: ThemeableWixel {
    let source: OwlSource

    static let kind = "owl"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomRight, offset: .init(width: 0, height: 150),
                                    size: .init(width: 90, height: 70)),
            build: { _, _ in Owl(source: OwlSource()) })
    }
    static let refresh: RefreshPolicy = .interval(7)   // wake within ~7s of return
    static let interactive = true
    static let px: CGFloat = 3
    static let blinkSeconds = 0.2

    // 15×14. D outline · B body · E eye white · p pupil · k beak · f foot · . empty
    static let owl: Sprite = [
        ".DD.........DD.",
        ".DBD.......DBD.",
        ".DBBD.....DBBD.",
        ".DBBBBBBBBBBBD.",
        "DBBBBBBBBBBBBBD",
        "DBEEEBBBBBEEEBD",
        "DBEpEBBBBBEpEBD",
        "DBEEEBBkBBEEEBD",
        "DBBBBBBkBBBBBBD",
        "DBBBBBBBBBBBBBD",
        ".DBBBBBBBBBBBD.",
        ".DBBBBBBBBBBBD.",
        "..DBBBBBBBBBD..",
        "...ff.....ff...",
    ]
    private static let eyesTop: [(Int, Int)] = [(5, 2), (5, 3), (5, 4), (5, 10), (5, 11), (5, 12)]
    private static let eyesAll: [(Int, Int)] = [
        (5, 2), (5, 3), (5, 4), (6, 2), (6, 3), (6, 4), (7, 2), (7, 3), (7, 4),
        (5, 10), (5, 11), (5, 12), (6, 10), (6, 11), (6, 12), (7, 10), (7, 11), (7, 12),
    ]
    private static let slit: [(Int, Int)] = [(6, 2), (6, 3), (6, 4), (6, 10), (6, 11), (6, 12)]

    static let drowsy = set(owl, eyesTop.map { ($0.0, $0.1, Character("B")) })          // half-lidded
    static let closed = set(set(owl, eyesAll.map { ($0.0, $0.1, Character("B")) }),
                            slit.map { ($0.0, $0.1, Character("D")) })                  // shut + slit

    func sample() async -> OwlState { await source.read() }
    func render(_ s: OwlState, _ theme: ThemeContext) -> some View { OwlView(state: s, theme: theme) }
}

private struct OwlView: View {
    let state: OwlState
    let theme: ThemeContext
    @State private var blinking = false

    // floating "z" specs while asleep (x from the right, size, timing)
    struct ZSpec { let x: CGFloat; let size: CGFloat; let delay: Double; let dur: Double }
    static let zs: [ZSpec] = [.init(x: 46, size: 11, delay: 0, dur: 2.4),
                              .init(x: 52, size: 14, delay: 1.2, dur: 2.8)]

    var body: some View {
        let palette: [Character: Color] = [
            "D": theme.color(.border), "B": theme.color(.accent),
            "E": theme.color(.foreground), "p": theme.color(.background),
            "k": theme.color(.warning), "f": theme.color(.warning),
        ]
        let asleep = state == .asleep
        let grid = (blinking || asleep) ? Owl.closed
                 : state == .drowsy ? Owl.drowsy : Owl.owl

        return ZStack(alignment: .topTrailing) {
            if asleep {
                ForEach(0..<OwlView.zs.count, id: \.self) { i in zLetter(OwlView.zs[i]) }
            }
            PixelStrip(frames: [grid], px: Owl.px, palette: palette)
        }
        .contentShape(Rectangle())
        .onTapGesture { blink() }
    }

    // a "z" rising and fading, like the JS owl-z animation
    private func zLetter(_ z: ZSpec) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (((t - z.delay) / z.dur).truncatingRemainder(dividingBy: 1) + 1)
                .truncatingRemainder(dividingBy: 1)
            let opacity = phase < 0.2 ? phase / 0.2 * 0.9 : max(0, 0.9 * (1 - (phase - 0.2) / 0.8))
            Text("z")
                .font(theme.font(.caption))
                .foregroundColor(theme.color(.foreground))
                .offset(x: -z.x, y: -4 - CGFloat(phase) * 20)
                .opacity(opacity)
        }
    }

    private func blink() { triggerTransient($blinking, for: Owl.blinkSeconds) }
}
