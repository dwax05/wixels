// Plant — port of cynaberii-plant: an ambient pixel plant you water by clicking.
// Each click drops water from above and advances one growth stage (planted →
// sprout → full → flowering → loop). At flowering, a click resets to bare soil.
// The stage + surprise bloom colour persist across launches via @AppStorage.
//
// No data source — the plant is click-driven; it only redraws on palette change
// (pot colours track wal) and on the local growth state. idleStatic sampling.
//
// Unlike the Übersicht original, there's no watering can — water just falls from
// the top of the pane onto the plant while it's growing.

import SwiftUI

struct Plant: Widget {
    static let kind = "plant"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec(_ s: Services) -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .topLeft, offset: .init(width: 40, height: -220),
                                    size: .init(width: 120, height: 130)),
            mount: { host, p in host.mount(Plant(), placement: p) })
    }
    static let refresh: RefreshPolicy = .idleStatic
    static let interactive = true

    static let nStages = 4
    static let waterSeconds = 0.75
    static let px: CGFloat = 5

    // fixed plant greens (not theme-matched), surprise bloom, yellow centre
    static let stem = RGB.from("#5f9e4f").color
    static let leaf = RGB.from("#7cc15f").color
    static let center = RGB.from("#ffd23f").color
    static let flowers: [Color] = ["#ff6b9d", "#c46fff", "#ff8c42", "#5ec8ff",
                                   "#ff5c5c", "#f4f4f4", "#ff9ecd"].map { RGB.from($0).color }

    // 13-wide grid. s stem · l leaf · f petal · x centre · r rim · m soil · p pot
    private static let e = "............."
    static let stages: [Sprite] = [
        // 0 just planted — a sprout pixel poking out of the soil
        [e, e, e, e, e, e, e, e, e, e, e, "......s......"],
        // 1 sprout
        [e, e, e, e, e, e, e, "......s......", ".....lsl.....", "......s......",
         ".....lsl.....", "......s......"],
        // 2 full
        [e, e, e, "......s......", ".....lsl.....", "......s......", ".....lsl.....",
         "......s......", ".....lsl.....", "......s......", ".....lsl.....", "......s......"],
        // 3 flowering
        [e, e, ".....fff.....", ".....fxf.....", ".....fff.....", "......s......",
         ".....lsl.....", "......s......", ".....lsl.....", "......s......",
         ".....lsl.....", "......s......"],
    ]
    static let pot: Sprite = ["..rrrrrrrrr..", "..mmmmmmmmm..", "..ppppppppp..", "...ppppppp..."]

    func sample() async -> Int { 0 }   // no external data; palette + @AppStorage drive it
    func render(_ s: Int, _ p: Palette) -> some View { PlantView(p: p) }
}

private struct PlantView: View {
    let p: Palette
    @AppStorage("cynPlantStage") private var stage = 0
    @AppStorage("cynPlantFlowerIdx") private var flowerIdx = 0
    @State private var watering = false

    var body: some View {
        let flower = Plant.flowers[flowerIdx % Plant.flowers.count]
        let palette: [Character: Color] = [
            "r": p.c(4).color,          // pot rim (accent)
            "m": p.c(1).color,          // soil
            "p": p.c(3).color,          // pot body (accent2)
            "s": Plant.stem, "l": Plant.leaf,
            "f": flower, "x": Plant.center,
        ]
        let grid = Plant.stages[stage] + Plant.pot

        return ZStack(alignment: .topLeading) {
            PixelStrip(frames: [grid], px: Plant.px, palette: palette)
            if watering {
                WaterDrops(color: p.c(6).color,
                           width: CGFloat(13) * Plant.px, height: CGFloat(16) * Plant.px)
            }
        }
        .pane(p)
        .contentShape(Rectangle())
        .onTapGesture { water() }
    }

    /// Click = water. Grows one stage after the splash; at the flowering stage a
    /// click resets to bare soil. Mid-water clicks are ignored (no stage-skipping).
    private func water() {
        guard !watering else { return }
        if stage == Plant.nStages - 1 { stage = 0; return }
        watering = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Plant.waterSeconds) {
            let next = (stage + 1) % Plant.nStages
            if next == Plant.nStages - 1 { flowerIdx = Int.random(in: 0..<Plant.flowers.count) }
            stage = next
            watering = false
        }
    }
}

/// Water falling from the top of the pane onto the plant — three staggered streams
/// that fan out slightly as they drop, looping for the watering window.
private struct WaterDrops: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let cx = width / 2                       // plant is centred in the grid
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ForEach(0..<3, id: \.self) { i in
                let dx: CGFloat = [-6, 0, 6][i]
                let phase = (((t - Double(i) * 0.05) / 0.55).truncatingRemainder(dividingBy: 1) + 1)
                    .truncatingRemainder(dividingBy: 1)
                let fall = CGFloat(phase) * (height * 0.5)
                Rectangle().fill(color)
                    .frame(width: max(1, Plant.px / 2), height: Plant.px)
                    .offset(x: cx + dx * CGFloat(phase), y: fall)
                    .opacity(phase < 0.85 ? 1 : max(0, 1 - (phase - 0.85) / 0.15))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}
