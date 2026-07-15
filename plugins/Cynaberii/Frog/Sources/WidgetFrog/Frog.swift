// Frog — port of cynaberii-frog: a pixel tree frog that hangs upside-down behind
// the clock card with just its head + eyes poking out below. It recolours with
// system thermal pressure (green → amber → red as the machine heats up) and sways
// like a pendulum — faster when warm, frozen when hot (so it adds no compositor
// load exactly when the CPU is already stressed). Clicking (or a random auto-poke)
// shoves it down out from behind the card and flicks its tongue.

import SwiftUI
import WixelsKit

struct Frog: ThemeableWixel {
    let source: FrogSource

    static let kind = "frog"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    /// Mounted before the clock (same window level) so the clock orders in front
    /// and hides the frog's body — keep frog above clock in Desktop.swift order.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .topCenter, offset: .init(width: 0, height: -136),
                                    size: .init(width: 100, height: 200)),
            build: { _, _ in Frog(source: FrogSource()) })
    }
    static let refresh: RefreshPolicy = .interval(8)   // thermal changes slowly
    static let interactive = true
    static let px: CGFloat = 4
    static let popPx: CGFloat = 26
    static let popSeconds = 1.1

    // upright tree frog (14×14); the view flips it so it hangs by its toe pads.
    // G body · D outline · e eye · g glint · b belly · t toe pad · . empty
    static let sprite: Sprite = [
        "..DD......DD..",
        ".DeeD....DeeD.",
        ".DgeD....DgeD.",
        "..DDGGGGGGDD..",
        ".DGGGGGGGGGGD.",
        "DGGGGGGGGGGGGD",
        "DGGGGbbbbGGGGD",
        "DGGGbbbbbbGGGD",
        ".DGGbbbbbbGGD.",
        ".DGGGGGGGGGGD.",
        "..DGGGGGGGGD..",
        "..DGGGGGGGGD..",
        ".DGGD....DGGD.",
        "tGGt......tGGt",
    ]

    func sample() async -> FrogState { await source.read() }
    func render(_ s: FrogState, _ theme: ThemeContext) -> some View { FrogView(state: s, theme: theme) }
}

/// All per-state frog attributes in one place — sway speed, freeze, body colour —
/// so a thermal-state change is a single edit here, not three scattered switches.
extension FrogState {
    /// Seconds per pendulum swing — slow when cool, quick when warm.
    var swayPeriod: Double {
        switch self { case .nominal: 3.6; case .fair: 3.0; case .serious: 1.9; case .critical: 1.3 }
    }
    /// Hot states freeze the sway (no compositor load while the CPU is stressed).
    var isHot: Bool { self == .serious || self == .critical }
    func bodyRole() -> ThemeSemanticColor {
        switch self {
        case .nominal: .positive; case .fair: .warning
        case .serious, .critical: .negative
        }
    }
}

private struct FrogView: View {
    let state: FrogState
    let theme: ThemeContext

    @State private var popOffset: CGFloat = 0
    @State private var tongueOut = false

    var body: some View {
        let palette: [Character: Color] = [
            "G": theme.color(state.bodyRole()), "D": theme.color(.border),
            "b": theme.color(.secondary), "e": theme.color(.background),
            "g": theme.color(.foreground), "t": theme.color(.alternateAccent),
        ]

        return frog(palette)
            .modifier(Sway(period: state.swayPeriod, frozen: state.isHot))
            .overlay(alignment: .bottom) {
                // tongue flicks down from the mouth (bottom, once flipped)
                Rectangle().fill(theme.color(.negative))
                    .frame(width: 2, height: 4 * Frog.px)
                    .scaleEffect(y: tongueOut ? 1 : 0, anchor: .top)
                    .offset(x: -1, y: 4 * Frog.px)
                    .opacity(tongueOut ? 1 : 0)
            }
            .offset(y: popOffset)                // shove down out from behind the card
            .contentShape(Rectangle())
            .onTapGesture { pop() }
            // pin to the top of a taller window so the pop-out + sway aren't clipped
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {                              // auto-poke on a random ~½-min cadence
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(.random(in: 25...45)))
                    pop()
                }
            }
    }

    // the frog, flipped vertically so it hangs by its toes
    private func frog(_ palette: [Character: Color]) -> some View {
        PixelStrip(frames: [Frog.sprite], px: Frog.px, palette: palette)
            .scaleEffect(x: 1, y: -1)
    }

    private func pop() {
        guard popOffset == 0 else { return }
        withAnimation(.easeInOut(duration: Frog.popSeconds * 0.28)) { popOffset = Frog.popPx }
        withAnimation(.easeInOut(duration: 0.24)) { tongueOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            withAnimation(.easeInOut(duration: 0.2)) { tongueOut = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Frog.popSeconds * 0.72) {
            withAnimation(.easeInOut(duration: Frog.popSeconds * 0.28)) { popOffset = 0 }
        }
    }
}

/// Pendulum sway from the top (the toe grip), ±3°, unless frozen (hot).
private struct Sway: ViewModifier {
    let period: Double
    let frozen: Bool

    func body(content: Content) -> some View {
        if frozen {
            content
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let angle = 3 * sin(t / period * 2 * .pi)
                content.rotationEffect(.degrees(angle), anchor: .top)
            }
        }
    }
}
