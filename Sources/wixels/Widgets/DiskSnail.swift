// DiskSnail — port of cynaberii-snail. An 18×15 pixel snail whose spiral shell
// fills bottom-up like a gauge as the root volume fills. Colours derive from the
// wal palette (body = color2) via mix/shade, exactly like the JS.
//
// idleStatic sampling: disk usage changes slowly (JS refreshes every 30s). The
// crawl below is view-side (time, not data), so no extra polling.
//
// Click pulls the snail's eyestalks in for a moment (shySeconds), same as the JS.
//
// Crawl: the snail orbits the cynaberii-sys box perimeter clockwise over 24h,
// upright along the top, rotated 90° down the right, upside-down along the
// bottom, 90° up the left, resetting at midnight (port of the JS perimeter walk).
// The snail's window is a transparent overlay covering the sys box + margins; the
// sprite is positioned/rotated inside it. Crawl.box* are tuned to the sys box.

import SwiftUI
import WixelsKit

struct DiskSnail: Wixel {
    let disk: DiskSource

    static let kind = "disk-snail"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .topLeft, offset: .init(width: -3, height: -30),
                                    size: .init(width: DiskSnail.Crawl.containerW,
                                                height: DiskSnail.Crawl.containerH)),
            build: { _, opts in erase(DiskSnail(disk: DiskSource(path: opts.string("path") ?? "/"))) })
    }
    static let refresh: RefreshPolicy = .idleStatic
    static let interactive = true
    static let shySeconds = 0.7

    /// Perimeter-crawl geometry. `box*` describe the sys box the snail rides
    /// around; tune them (and the snail window's offset in main.swift) to sit the
    /// path snugly outside the real box + its 6px drop shadow.
    enum Crawl {
        static let boxW: CGFloat = 155     // sys box visible width  (tune to fit)
        static let boxH: CGFloat = 90      // sys box visible height (tune to fit)
        static let outPx: CGFloat = 16     // how far outside the edge the snail rides
        static let shadow: CGFloat = 6     // sys box boxShadow (right + down)
        static let px: CGFloat = 3         // sprite scale
        static let sw: CGFloat = 18 * px   // sprite width  (54)
        static let sh: CGFloat = 15 * px   // sprite height (45)

        // the overlay window that contains the whole crawl path + sprite
        static var containerW: CGFloat { boxW + 2 * outPx + shadow + sw }
        static var containerH: CGFloat { boxH + 2 * outPx + shadow + sh }

        /// Top-leading offset (within the container) + rotation for the sprite at
        /// the given time-of-day. Clockwise from the box's top-left corner.
        static func place(_ date: Date) -> (x: CGFloat, y: CGFloat, rot: Double) {
            let M = sw / 2                                   // corner inset along travel
            let left = -outPx, top = -outPx
            let right = boxW + outPx + shadow, bot = boxH + outPx + shadow
            let topLen = (right - M) - (left + M)
            let sideLen = (bot - M) - (top + M)
            let total = 2 * topLen + 2 * sideLen

            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let h = Double(c.hour ?? 0), m = Double(c.minute ?? 0), s = Double(c.second ?? 0)
            let secs = h * 3600 + m * 60 + s
            var dist = (secs / 86400) * total

            // walk the four edges clockwise, consuming `dist`
            var cx: CGFloat = left, cy: CGFloat = top, rot = 0.0
            if dist < topLen {                                     // top →
                cx = left + M + dist; cy = top; rot = 0
            } else if dist < topLen + sideLen {                    // right ↓
                dist -= topLen
                cx = right; cy = top + M + dist; rot = 90
            } else if dist < 2 * topLen + sideLen {                // bottom ← (upside down)
                dist -= topLen + sideLen
                cx = right - M - dist; cy = bot; rot = 180
            } else {                                               // left ↑
                dist -= 2 * topLen + sideLen
                cx = left; cy = bot - M - dist; rot = 270
            }

            // sprite centre = (cx,cy) in box coords; container origin is outPx+sw/2
            // to the top-left of the box, so top-leading = centre - sprite/2 + pad.
            return (cx + outPx, cy + outPx, rot)
        }
    }

    // 18 wide × 15 tall. D outline · B body/foot · H shell interior (fill gauge)
    // · o eye · . empty
    static let sprite: Sprite = [
        "..................",
        "....DDDDD.........",
        "...DDDHHDD........",
        "..DDHHHHHHD.......",
        ".DDHHDDDDHDD......",
        ".DDHHDHHDHHD.D..D.",
        ".DDHHDDHHDHD.o..o.",
        ".DDHHDDHHDHD.D..D.",
        ".DDDHHHHDHDD.D..D.",
        "..DHDDDDDHD..D..D.",
        "...DDHHHDD...DBBD.",
        "....DDDDD...DBBBB.",
        "...B.........DBBD.",
        "...BBBBBBBBBBBBBB.",
        "....DDDDDDDDDDDD..",
    ]

    // shy: eyestalks + eyes pulled in (STALKS cells cleared to empty)
    static let stalks: [(Int, Int)] = [
        (5, 12), (5, 13), (5, 15), (5, 16),
        (6, 12), (6, 13), (6, 15), (6, 16),
        (7, 13), (7, 16), (8, 13), (8, 16), (9, 13), (9, 16),
    ]
    static let spriteShy: Sprite = set(sprite, stalks.map { ($0.0, $0.1, Character(".")) })

    func sample() async -> DiskInfo { await disk.read() }

    func render(_ s: DiskInfo, _ p: Palette) -> some View { SnailView(info: s, p: p) }
}

/// The snail as a stateful view so a click can tuck its eyestalks in for a beat,
/// like the JS component's useState(shy). render() stays a pure map to this view.
private struct SnailView: View {
    let info: DiskInfo
    let p: Palette
    @State private var shy = false

    var body: some View {
        let disk = max(0, min(100, info.usedFraction * 100))
        let high = disk >= 90                          // nearly-full drive flushes warm
        let body = p.c(2)
        let palette: [Character: Color] = [
            "D": body.shade(0.5).color,                // outline
            "B": body.color,                           // foot/head
            "F": (high ? p.c(1) : p.c(4)).color,       // filled shell
            "e": body.mix(p.background, 0.65).color,   // empty shell
            "o": p.foreground.color,                   // eyes
        ]
        let grid = fillShell(shy ? DiskSnail.spriteShy : DiskSnail.sprite, disk)
        // Re-evaluate the crawl position periodically (the snail moves ~18px/hr,
        // so 30s is smooth). The sprite rotates + rides the sys box perimeter.
        return TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let pos = DiskSnail.Crawl.place(ctx.date)
            ZStack(alignment: .topLeading) {
                PixelStrip(frames: [grid], px: DiskSnail.Crawl.px, palette: palette)
                    .rotationEffect(.degrees(pos.rot))
                    .offset(x: pos.x, y: pos.y)
                    .contentShape(Rectangle())
                    .onTapGesture { poke() }
            }
            .frame(width: DiskSnail.Crawl.containerW,
                   height: DiskSnail.Crawl.containerH, alignment: .topLeading)
        }
    }

    private func poke() {
        triggerTransient($shy, for: DiskSnail.shySeconds, animated: true)
    }
}
