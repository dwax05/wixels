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
import WixelsKit

struct Plant: ThemeableWixel {
    static let kind = "plant"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .topLeft, offset: .init(width: 40, height: -220),
                                    size: .init(width: 120, height: 130), sizing: .fitContent),
            build: { _, _ in Plant() })
    }
    static let refresh: RefreshPolicy = .idleStatic
    static let interactive = true

    static let nStages = 4
    static let waterSeconds = 0.75
    static let px: CGFloat = 5
    // Preserve the Übersicht plant's surprise blooms. Yellow is intentionally
    // excluded so the fixed centre always reads as a separate pixel cluster.
    static let flowerColors = ["FF6B9D", "C46FFF", "FF8C42", "5EC8FF", "FF5C5C", "F4F4F4", "FF9ECD"]
        .map(RGB.from)
    static let flowerCenter = RGB.from("FFD23F")
    static let stem = RGB.from("5F9E4F")
    static let leaf = RGB.from("7CC15F")

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
    func render(_ s: Int, _ theme: ThemeContext) -> some View { PlantView(theme: theme) }
}

private struct PlantView: View {
    let theme: ThemeContext
    @AppStorage("cynPlantStage") private var stage = 0
    @AppStorage("cynPlantFlowerIdx") private var flowerIdx = 0
    @State private var watering = false

    var body: some View {
        let flower = Plant.flowerColors[flowerIdx % Plant.flowerColors.count].color
        let palette: [Character: Color] = [
            "r": theme.color(.accent), "m": theme.color(.negative),
            "p": theme.color(.alternateAccent),
            "s": Plant.stem.color, "l": Plant.leaf.color,
            "f": flower, "x": Plant.flowerCenter.color,
        ]
        let grid = Plant.stages[stage] + Plant.pot

        return ZStack(alignment: .topLeading) {
            PixelStrip(frames: [grid], px: Plant.px, palette: palette)
            if watering {
                WaterDrops(color: theme.color(.secondary),
                           width: CGFloat(13) * Plant.px, height: CGFloat(16) * Plant.px)
            }
        }
        .themedCard(theme)
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
            if next == Plant.nStages - 1 { flowerIdx = Int.random(in: 0..<Plant.flowerColors.count) }
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
        ForEach(0..<3, id: \.self) { i in
            let dx: CGFloat = [-6, 0, 6][i]
            Rectangle().fill(color)
                .frame(width: max(1, Plant.px / 2), height: Plant.px)
                .offset(x: cx, y: 0)
                .loopEffect([
                    .sampled(.offsetX, duration: 0.55, fps: 30, delay: Double(i) * 0.05) { dx * $0 },
                    .sampled(.offsetY, duration: 0.55, fps: 30, delay: Double(i) * 0.05) { height * 0.5 * $0 },
                    .sampled(.opacity, duration: 0.55, fps: 30, delay: Double(i) * 0.05) { $0 < 0.85 ? 1 : max(0, 1 - ($0 - 0.85) / 0.15) },
                ])
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}
