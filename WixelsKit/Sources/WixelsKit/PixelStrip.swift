// PixelStrip — the shared sprite renderer every cynaberii widget draws through.
// A sprite is a grid of Characters; a palette maps each Character to an RGB (or
// nothing = transparent). We draw each set cell as a scaled, crisp 1×1 pixel.
//
// Multi-frame sprites animate by cycling the frame index every `frameMS` (the
// port of Übersicht's `steps()` strip scroll). A single-frame sprite draws
// statically — no animation, so the compositor stays idle (the battery rule).

import AppKit
import SwiftUI

/// Decode raw base64 artwork into an image (nil when absent/undecodable). Shared by
/// the cassette (NowPlaying) + poster cards.
public func decodeArtwork(_ b64: String) -> NSImage? {
    guard !b64.isEmpty,
          let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    else { return nil }
    return NSImage(data: data)
}

public typealias Sprite = [String]   // rows of equal-length character strings
public typealias Cell = (row: Int, col: Int, ch: Character)   // one grid edit — named, not $0.0/$0.1

// MARK: - Grid helpers (ports of the JS `set` / `fillShell`)

/// Overwrite individual cells (out-of-bounds edits are ignored).
public func set(_ grid: Sprite, _ cells: [Cell]) -> Sprite {
    var g = grid.map { Array($0) }
    for cell in cells where g.indices.contains(cell.row) && g[cell.row].indices.contains(cell.col) {
        g[cell.row][cell.col] = cell.ch
    }
    return g.map { String($0) }
}

/// Fill the shell interior ('H') bottom-up to `pct` (0…100), marking cells
/// 'F'(illed) below the line and 'e'(mpty) above — the disk-snail gauge.
public func fillShell(_ grid: Sprite, _ pct: Double) -> Sprite {
    let hRows = grid.enumerated().filter { $0.element.contains("H") }.map { $0.offset }
    guard let top = hRows.min(), let bot = hRows.max() else { return grid }
    let line = Double(bot) - (pct / 100) * Double(bot - top + 1)
    return grid.enumerated().map { y, row in
        String(row.map { $0 == "H" ? (Double(y) >= line ? "F" : "e") : $0 })
    }
}

// MARK: - Renderer

/// One frame drawn as crisp scaled pixels via a Canvas (single draw call, GPU
/// composited, cheap).
struct PixelFrame: View {
    let grid: Sprite
    let px: CGFloat
    let palette: [Character: Color]

    var body: some View {
        let cols = grid.first?.count ?? 0
        let rows = grid.count
        Canvas { ctx, _ in
            for (r, line) in grid.enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let color = palette[ch] else { continue }
                    let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px, height: px)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(cols) * px, height: CGFloat(rows) * px)
    }
}

/// A sprite that may have multiple frames. One frame → static. Many frames →
/// cycle at `frameMS`. Use a periodic schedule rather than `.animation`: pixel
/// sprites have a discrete frame rate, so asking SwiftUI to redraw at display
/// refresh wastes GPU wakeups between frames.
public struct PixelStrip: View {
    let frames: [Sprite]
    let px: CGFloat
    let palette: [Character: Color]
    var frameMS: Double = 0

    public init(frames: [Sprite], px: CGFloat, palette: [Character: Color], frameMS: Double = 0) {
        self.frames = frames; self.px = px; self.palette = palette; self.frameMS = frameMS
    }

    public var body: some View {
        if ProcessInfo.processInfo.environment["WIXELS_NO_CA"] == "1" {
            // A/B escape hatch: retain the previous Canvas renderer when CA
            // behavior needs to be compared on a particular macOS release.
            if frames.count > 1 && frameMS > 0 {
                TimelineView(.periodic(from: .now, by: frameMS / 1000)) { ctx in
                    let i = Int((ctx.date.timeIntervalSinceReferenceDate * 1000 / frameMS).rounded(.down)) % frames.count
                    PixelFrame(grid: frames[i], px: px, palette: palette)
                }
            } else {
                PixelFrame(grid: frames.first ?? [], px: px, palette: palette)
            }
        } else {
            AnimatedSprite(frames: frames, px: px, palette: palette, frameMS: frameMS)
        }
    }
}

/// A pixel sprite that rises and fades on a loop. This is the one shape behind
/// both the cat's hearts and its music notes — they were the same phase/opacity
/// math with different constants, so they share this now.
///   fadeIn   — phase fraction (0…1) spent fading in before fading back out
///   rise     — px travelled upward across one loop
///   scaleGrow— extra scale gained over the loop (0 = constant size)
public struct RisingParticle: View {
    let sprite: Sprite
    let palette: [Character: Color]
    let size: CGFloat
    let x: CGFloat
    let baseY: CGFloat
    let rise: CGFloat
    let fadeIn: Double
    let delay: Double
    let dur: Double
    let rot: Double
    var scaleGrow: CGFloat = 0
    var frameRate: Double = 12

    public init(sprite: Sprite, palette: [Character: Color], size: CGFloat, x: CGFloat,
                baseY: CGFloat, rise: CGFloat, fadeIn: Double, delay: Double, dur: Double,
                rot: Double, scaleGrow: CGFloat = 0, frameRate: Double = 12) {
        self.sprite = sprite; self.palette = palette; self.size = size; self.x = x
        self.baseY = baseY; self.rise = rise; self.fadeIn = fadeIn; self.delay = delay
        self.dur = dur; self.rot = rot; self.scaleGrow = scaleGrow; self.frameRate = frameRate
    }

    public var body: some View {
        let tracks = [
            LoopTrack.sampled(.offsetY, duration: dur, fps: frameRate, delay: delay) { -$0 * rise },
            LoopTrack.sampled(.opacity, duration: dur, fps: frameRate, delay: delay) { phase in
                phase < fadeIn ? phase / fadeIn : max(0, 1 - (phase - fadeIn) / (1 - fadeIn))
            },
            LoopTrack.sampled(.scale, duration: dur, fps: frameRate, delay: delay) { (1 - scaleGrow) + $0 * scaleGrow },
        ]
        AnimatedSprite(frames: [sprite], px: size, palette: palette, motion: tracks)
            .rotationEffect(.degrees(rot))
            .offset(x: x, y: baseY)
    }
}

/// Fire a one-shot transient reaction: flip `flag` true now, back to false after
/// `seconds`, ignoring re-entry while it's already active. Both widgets' tap
/// reactions (the snail's shy tuck, the cat's happy burst) are this same shape.
@MainActor
public func triggerTransient(_ flag: Binding<Bool>, for seconds: Double,
                      animated: Bool = false, onReset: @escaping () -> Void = {}) {
    guard !flag.wrappedValue else { return }
    if animated { withAnimation(.easeOut(duration: 0.12)) { flag.wrappedValue = true } }
    else { flag.wrappedValue = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        if animated { withAnimation(.easeIn(duration: 0.15)) { flag.wrappedValue = false } }
        else { flag.wrappedValue = false }
        onReset()
    }
}
