// CatPet — port of cynaberii-pet, a full-body 16×17 cinnabar cat that reacts to
// the system. Multi-frame states scroll like the JS steps() strip:
//   idle → static blink-rest   sleep → CPU idle, "z"s
//   run  → CPU busy, sweat      eat   → network active, chewing
//   + blush when charging (any state)
//
// interval(10s): pet.py's heaviest poll cadence. Data (mood) refreshes on the
// shared scheduler; the sprite animation runs independently via PixelStrip.
//
// Music (headphones + drifting notes) comes from MusicMonitor (MediaRemote).
//
// Click reaction: happy face (closed-eye smile + blush) + a burst of rising
// hearts for petSeconds, ported from the JS useState(petting).

import SwiftUI
import WixelsKit

struct CatPet: ThemeableWixel {
    let source: PetSource

    static let kind = "pet"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomLeft, offset: .init(width: 224, height: 116),
                                    size: .init(width: 92, height: 106), sizing: .fitContent),
            build: { s, _ in CatPet(source: PetSource(cpu: s.cpu, music: s.music)) })
    }
    static let refresh: RefreshPolicy = .interval(3)   // native sources are cheap, so poll snappier than pet.py's 10s
    static let interactive = true
    static let petSeconds = 1.5                        // how long the happy reaction lasts

    func sample() async -> PetState { await source.read() }

    // ── full-body sitting cat (16 wide × 17 tall) ──
    //  B fur · D outline · e eye · n nose · w mouth · i inner-ear · . empty
    static let raw: Sprite = [
        "...D........D...",
        "..DiD......DiD..",
        "..DiiD....DiiD..",
        "..DBBDDDDDDBBD..",
        ".DBBBBBBBBBBBBD.",
        ".DBBBBBBBBBBBBD.",
        "DBBeBBBBBBBBeBBD",
        "DBBeBBBBBBBBeBBD",
        "DBBBBBBnnBBBBBBD",
        "DBBBBBnwwnBBBBBD",
        ".DBBBBBBBBBBBBD.",
        ".DDBBBBBBBBBBDD.",
        "..DBBBBBBBBBBD..",
        "..DBBBBBBBBBBD..",
        "..DBBBBBBBBBBD..",
        "..DBBDDDDDDBBD..",
        "...DDD....DDD...",
    ]
    // curled tail down the lower-right
    static let base: Sprite = set(raw, [
        (12, 14, "D"), (13, 14, "B"), (13, 15, "D"),
        (14, 14, "B"), (14, 15, "D"), (15, 14, "D"), (15, 15, "D"),
    ])

    // feature cell groups
    static let eyes: [(Int, Int)] = [(6, 3), (7, 3), (6, 12), (7, 12)]
    static func closeEyes(_ ch: Character) -> [(Int, Int, Character)] { eyes.map { ($0.0, $0.1, ch) } }
    static let openMouth: [(Int, Int, Character)] = [(9, 7, "m"), (9, 8, "m")]
    static let cheeks: [(Int, Int, Character)] = [(8, 2, "c"), (8, 13, "c")]
    static let sweat: (Int, Int, Character) = (4, 14, "s")

    /// Frame list + per-frame duration for a mood, blush overlaid when charging.
    static func frames(for mood: PetMood, charging: Bool) -> (frames: [Sprite], ms: Double) {
        let blush = charging ? cheeks : []
        let out: (frames: [Sprite], ms: Double)
        switch mood {
        case .sleep:
            out = ([set(base, closeEyes("D") + [(1, 14, "z")]),
                    set(base, closeEyes("D") + [(0, 15, "z")])], 1600)
        case .run:
            out = ([set(base, openMouth + [sweat]), set(base, openMouth)], 320)
        case .eat:
            out = ([set(base, openMouth), base], 380)
        case .idle:
            out = ([base], 0)           // single static frame — compositor idles
        }
        return (out.frames.map { set($0, blush) }, out.ms)
    }

    // Over-ear headphones in the cat's own 16×17 grid — band arcs over the crown,
    // cups on the sides. P = band/cup shell · U = cushion · . = empty
    static let headphones: Sprite = [
        "................",
        "................",
        "...PPPPPPPPPP...",
        "..PP........PP..",
        ".PP..........PP.",
        ".P............P.",
        "PUP..........PUP",
        "PUP..........PUP",
        ".P............P.",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ]
    // little eighth-note (3×5): X = ink
    static let note: Sprite = ["..X", "..X", "..X", "XXX", "XX."]

    // happy "being petted" face: closed eyes + blush + little open smile
    static let happy: Sprite = set(base, closeEyes("D") + cheeks + openMouth)
    // floating heart (5×4) for the pet reaction — X = fixed bright pink
    static let bigHeart: Sprite = ["XX.XX", "XXXXX", ".XXX.", "..X.."]

    // sprite is 48×51 at px=3; the outer frame adds headroom above for notes.
    static let px: CGFloat = 3
    static let frameW: CGFloat = 16 * px, frameH: CGFloat = 17 * px
    static let boxW: CGFloat = 72, boxH: CGFloat = 96

    func render(_ s: PetState, _ theme: ThemeContext) -> some View { PetView(s: s, theme: theme) }
}

/// The pet as a stateful view: a click makes it happy (closed-eye smile + bounce)
/// and bursts hearts for petSeconds, like the JS useState(petting). render() stays
/// a pure map to this view; the transient reaction lives here.
private struct PetView: View {
    let s: PetState
    let theme: ThemeContext
    @State private var petting = false
    @State private var hearts: [Heart] = []

    struct Heart: Identifiable {
        let id = UUID()
        let x: CGFloat; let top: CGFloat; let size: CGFloat
        let delay: Double; let dur: Double; let rot: Double
    }

    var body: some View {
        let palette: [Character: Color] = [
            "B": theme.color(.accent), "D": theme.color(.alternateAccent),
            "e": theme.color(.background), "n": theme.color(.positive),
            "w": theme.color(.alternateAccent), "i": theme.color(.positive),
            "m": theme.color(.muted), "c": theme.color(.positive),
            "s": theme.color(.secondary), "z": theme.color(.foreground),
        ]
        // petting overrides the system-state animation with the happy face
        let anim: (frames: [Sprite], ms: Double) = petting
            ? ([CatPet.happy], 0)
            : CatPet.frames(for: s.mood, charging: s.charging)
        let noteColors = [theme.color(.secondary), theme.color(.positive), theme.color(.foreground)]

        return ZStack(alignment: .bottom) {
            // cat body on its own pane first, so particles (below) layer on top
            ZStack(alignment: .topLeading) {
                PixelStrip(frames: anim.frames, px: CatPet.px, palette: palette, frameMS: anim.ms)
                if s.music {
                    PixelStrip(frames: [CatPet.headphones], px: CatPet.px,
                               palette: ["P": theme.color(.foreground), "U": theme.color(.secondary)])
                }
            }
            .modifier(Wiggle(mood: s.mood, music: s.music, happy: petting))
            // particles on top of everything
            if s.music {
                NotesLayer(colors: noteColors)
                    .frame(width: CatPet.boxW, height: CatPet.boxH, alignment: .top)
            }
            // hearts burst (rise + fade, port of pet-heart)
            ForEach(hearts) { h in
                RisingParticle(sprite: CatPet.bigHeart, palette: ["X": theme.color(.negative)],
                               size: h.size, x: h.x, baseY: h.top, rise: 26, fadeIn: 0.25,
                               delay: h.delay, dur: h.dur, rot: h.rot, scaleGrow: 0.3)
            }
        }
        .frame(width: CatPet.boxW, height: CatPet.boxH, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { pet() }
    }

    private func pet() {
        guard !petting else { return }
        hearts = PetView.makeHearts()
        triggerTransient($petting, for: CatPet.petSeconds) { hearts = [] }
    }

    static func makeHearts() -> [Heart] {
        (0..<(5 + Int.random(in: 0...2))).map { _ in
            Heart(x: -16 + .random(in: 0...32), top: -46 + .random(in: 0...12),
                  size: CGFloat(3 + Int.random(in: 0...1)),
                  delay: .random(in: 0...0.55), dur: 0.9 + .random(in: 0...0.6),
                  rot: .random(in: -20...20))
        }
    }
}

/// Notes drifting up off the cat while a song plays. Fixed staggered specs (not
/// regenerated per frame) so the motion stays smooth — port of NOTE_SPECS. Each
/// note is a RisingParticle (same rise/fade shape as the hearts).
struct NotesLayer: View {
    let colors: [Color]

    struct Spec { let x: CGFloat; let size: CGFloat; let delay: Double; let dur: Double; let rot: Double }
    static let specs: [Spec] = [
        .init(x: 16, size: 3, delay: 0.0, dur: 2.0, rot: -12),
        .init(x: 30, size: 4, delay: 0.7, dur: 2.3, rot: 10),
        .init(x: 22, size: 3, delay: 1.4, dur: 2.1, rot: 18),
        .init(x: 40, size: 3, delay: 1.0, dur: 2.4, rot: -6),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(NotesLayer.specs.enumerated()), id: \.offset) { i, spec in
                RisingParticle(sprite: CatPet.note, palette: ["X": colors[i % colors.count]],
                               size: spec.size, x: spec.x, baseY: 44, rise: 40, fadeIn: 0.18,
                               delay: spec.delay, dur: spec.dur, rot: spec.rot, frameRate: 24)
            }
        }
    }
}

/// Outer body motion (ports the JS pet-wiggle / pet-bob / pet-groove). Priority
/// matches the JS: run and sleep override music; music grooves in idle/eat;
/// otherwise no animation at all, so the compositor stays idle.
struct Wiggle: ViewModifier {
    let mood: PetMood
    let music: Bool
    var happy: Bool = false

    func body(content: Content) -> some View {
        if happy {
            content.loopEffect([.sampled(.offsetY, duration: 0.45, fps: 30) { -3 * sin($0 * .pi) }, .sampled(.scaleY, duration: 0.45, fps: 30) { 1 - 0.07 * $0 }])
        } else if mood == .run {
            content.loopEffect([.init(.offsetX, values: [-1, 1], duration: 0.28, discrete: true)])
        } else if mood == .sleep {
            content.loopEffect([.sampled(.offsetY, duration: 2.8, fps: 30) { sin($0 * 2 * .pi) * 2 }])
        } else if music {
            content.loopEffect([.sampled(.rotationDegrees, duration: 0.6, fps: 30) { -2 * cos($0 * 2 * .pi) }, .sampled(.offsetY, duration: 0.6, fps: 30) { -(1 - cos($0 * 2 * .pi)) }], anchor: .bottom)
        } else {
            content
        }
    }
}
