// PixelClock — port of cynaberii-clock: chunky wal-coloured pixel digits (HH:MM, 12h)
// with a blinking colon and a date line, on a card pane. Time is computed locally;
// the palette drives the colours. A TimelineView redraws once a second (for the
// colon blink); the digits only change on the minute. idleStatic: no polling.

import SwiftUI
import WixelsKit

struct PixelClock: Wixel {
    static let kind = "clock"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    /// zBoost: 1 keeps the clock above the frog it hides, even after a click reorders.
    static func spec() -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .topCenter, offset: .init(width: 0, height: -70),
                                    size: .init(width: 220, height: 120), zBoost: 1),
            build: { _, _ in erase(PixelClock()) })
    }
    static let refresh: RefreshPolicy = .idleStatic
    // interactive (no click action) only so it shares the frog's window level and
    // can be ordered in front of it — the clock card hides the frog's body.
    static let interactive = true
    static let px: CGFloat = 9

    // 3×5 pixel digit font (colon is 1-wide, drawn separately so it can blink)
    static let font: [Character: [String]] = [
        "0": ["###", "# #", "# #", "# #", "###"],
        "1": ["  #", "  #", "  #", "  #", "  #"],
        "2": ["###", "  #", "###", "#  ", "###"],
        "3": ["###", "  #", "###", "  #", "###"],
        "4": ["# #", "# #", "###", "  #", "  #"],
        "5": ["###", "#  ", "###", "  #", "###"],
        "6": ["###", "#  ", "###", "# #", "###"],
        "7": ["###", "  #", "  #", "  #", "  #"],
        "8": ["###", "# #", "###", "# #", "###"],
        "9": ["###", "# #", "###", "  #", "###"],
    ]
    static let colon: Sprite = [" ", " ", "#", " ", "#"]

    /// Lay a digit string into a 5-row sprite with a 1-col gap between glyphs.
    static func digits(_ s: String) -> Sprite {
        let glyphs = s.map { font[$0] ?? font["0"]! }
        return (0..<5).map { r in
            glyphs.enumerated().map { i, g in g[r] + (i < glyphs.count - 1 ? " " : "") }.joined()
        }
    }

    func sample() async -> Int { 0 }   // time is view-side; palette drives colours
    func render(_ s: Int, _ p: Palette) -> some View { ClockView(p: p) }
}

private struct ClockView: View {
    let p: Palette

    static let days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                         "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    var body: some View {
        let accent = p.c(4).color
        let digitPal: [Character: Color] = ["#": accent]

        // one redraw a second — cheap, and lets the colon blink without a scheduler
        return TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let c = Calendar.current.dateComponents(
                [.hour, .minute, .second, .weekday, .month, .day], from: ctx.date)
            let hour12 = (c.hour ?? 0) % 12 == 0 ? 12 : (c.hour ?? 0) % 12
            let hh = String(format: "%02d", hour12)
            let mm = String(format: "%02d", c.minute ?? 0)
            let colonOn = (c.second ?? 0) % 2 == 0
            let date = "\(ClockView.days[(c.weekday ?? 1) - 1]) "
                + "\(ClockView.months[(c.month ?? 1) - 1]) \(c.day ?? 1)"

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: PixelClock.px) {
                    PixelStrip(frames: [PixelClock.digits(hh)], px: PixelClock.px, palette: digitPal)
                    PixelStrip(frames: [PixelClock.colon], px: PixelClock.px, palette: digitPal)
                        .opacity(colonOn ? 1 : 0)
                    PixelStrip(frames: [PixelClock.digits(mm)], px: PixelClock.px, palette: digitPal)
                }
                Text(date)
                    .font(.pixel(12))
                    .tracking(2)
                    .foregroundColor(p.c(6).color)      // sage
            }
        }
        .pane(p, insets: .init(top: 16, leading: 22, bottom: 16, trailing: 22))
    }
}
