// Poster — port of cynaberii-poster: a polaroid-style now-playing card that, unlike
// every other widget, recolours from the ALBUM COVER (not wal). The cover's pixels
// are quantised into a palette (paper/ink/accent/frame + a 6-swatch bar) natively
// with CoreGraphics — the JS did this in a canvas. Only shows while a track is
// loaded. Outer border/shadow still track wal so it sits in the set.

import AppKit
import SwiftUI
import WixelsKit

struct Poster: ThemeableWixel {
    let monitor: MusicMonitor

    static let kind = "poster"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .topRight, offset: .init(width: 0, height: -220),
                                    size: .init(width: 230, height: 460), align: .trailing),
            build: { s, _ in Poster(monitor: s.music) })
    }
    static let refresh: RefreshPolicy = .interval(4)
    static let interactive = true
    static let artW: CGFloat = 200      // cover edge (px)

    func sample() async -> PosterInfo { await monitor.poster() }
    func render(_ s: PosterInfo, _ theme: ThemeContext) -> some View { PosterView(info: s, theme: theme, monitor: monitor) }
}

/// Palette pulled from the album cover — drives everything inside the card.
struct CoverPalette: Equatable, Sendable {
    var paper, ink, inkSoft, accent, frame: Color
    var swatch: [Color]

    static func hex(_ h: String) -> Color { RGB.from(h).color }
    static let fallback = CoverPalette(
        paper: hex("#e9e4d8"), ink: hex("#1c1a20"), inkSoft: hex("#5b564e"),
        accent: hex("#1DB954"), frame: hex("#cfc9bb"),
        swatch: ["#6b5b53", "#a9795f", "#5f86a8", "#c99f7a", "#9db4c4", "#c7c2b8"].map(hex))

    /// Quantise the cover into a palette (port of the JS extractPalette).
    static func extract(_ image: NSImage) -> CoverPalette? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let n = 56
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var buckets: [Int: (n: Int, r: Double, g: Double, b: Double)] = [:]
        var i = 0
        while i < buf.count {
            if buf[i + 3] >= 125 {
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                let key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
                var e = buckets[key] ?? (0, 0, 0, 0)
                e.n += 1; e.r += Double(r); e.g += Double(g); e.b += Double(b)
                buckets[key] = e
            }
            i += 4
        }
        let all = buckets.values
            .map { (n: $0.n, c: [$0.r / Double($0.n), $0.g / Double($0.n), $0.b / Double($0.n)]) }
            .sorted { $0.n > $1.n }
        guard let first = all.first else { return nil }

        var swatch: [[Double]] = []
        for e in all {
            if swatch.allSatisfy({ dist($0, e.c) > 60 }) { swatch.append(e.c) }
            if swatch.count >= 6 { break }
        }
        while swatch.count < 6 { swatch.append(first.c) }

        let vibrant = all.prefix(12)
            .max { sat($0.c) * pow(Double($0.n), 0.3) < sat($1.c) * pow(Double($1.n), 0.3) }?.c ?? first.c

        let top = all.prefix(6)
        let wsum = Double(top.reduce(0) { $0 + $1.n })
        var avg = [0.0, 0, 0]
        for e in top { for k in 0..<3 { avg[k] += e.c[k] * Double(e.n) / wsum } }

        let paper = mix(avg, [255, 255, 255], 0.8)
        var ink = mix(avg, [22, 20, 26], 0.72)
        if lum(ink) > 0.42 { ink = mix(ink, [12, 10, 14], 0.6) }
        let frame = mix(avg, [255, 255, 255], 0.55)
        let sortedSwatch = swatch.sorted { hue($0) < hue($1) }

        return CoverPalette(paper: col(paper), ink: col(ink), inkSoft: col(mix(ink, paper, 0.35)),
                            accent: col(vibrant), frame: col(frame), swatch: sortedSwatch.map(col))
    }

    // colour maths on [r,g,b] in 0…255
    private static func mix(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
        (0..<3).map { a[$0] + (b[$0] - a[$0]) * t }
    }
    private static func lum(_ c: [Double]) -> Double { (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255 }
    private static func sat(_ c: [Double]) -> Double {
        let mx = c.max()!, mn = c.min()!
        return mx == 0 ? 0 : (mx - mn) / mx
    }
    private static func hue(_ c: [Double]) -> Double {
        let r = c[0] / 255, g = c[1] / 255, b = c[2] / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d != 0 else { return 0 }
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
    private static func dist(_ a: [Double], _ b: [Double]) -> Double {
        abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
    }
    private static func col(_ c: [Double]) -> Color {
        Color(red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255)
    }
}

private struct PosterView: View {
    let info: PosterInfo
    let theme: ThemeContext
    let monitor: MusicMonitor

    @State private var art: NSImage?
    @State private var cover: CoverPalette = .fallback
    @State private var override = PlayOverride()
    @State private var shuffleOn = false
    @State private var liked = false

    private var shownPlaying: Bool { override.resolve(info.playing) }

    var body: some View {
        // idle → render nothing (keeps the right side clean)
        if !info.hasTrack {
            Color.clear.frame(width: 1, height: 1)
        } else {
            card
        }
    }

    private var card: some View {
        let wAccent = theme.color(.accent)
        let cp = cover

        return VStack(alignment: .leading, spacing: 0) {
            // "♪ now playing" caption
            HStack(spacing: 5) {
                Text("♪"); Text("NOW PLAYING")
            }
            .font(theme.font(.caption)).tracking(1).foregroundColor(wAccent)
            .padding(.bottom, 9)

            // cover
            coverImage(cp)

            // swatch bar
            HStack(spacing: 0) {
                ForEach(Array(cp.swatch.enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(c).frame(maxWidth: .infinity)
                }
            }
            .frame(width: Poster.artW, height: 16)
            .padding(.top, 10)

            // title + duration
            HStack(alignment: .top, spacing: 8) {
                Text(info.title.uppercased())
                    .font(theme.font(.body)).tracking(0.3).foregroundColor(cp.ink)
                    .lineLimit(2).frame(height: 31, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !info.duration.isEmpty {
                    Text(info.duration).font(theme.font(.label)).foregroundColor(cp.ink)
                }
            }
            .padding(.top, 12)

            // artist + controls
            HStack(spacing: 8) {
                Text(info.artist).font(theme.font(.label)).foregroundColor(cp.ink)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    icon(shownPlaying ? "pause.fill" : "play.fill", cp.ink) { togglePlay() }
                    icon("shuffle", shuffleOn ? wAccent : cp.ink) {
                        Task { await monitor.toggleShuffle() }; shuffleOn.toggle()
                    }
                    icon("forward.fill", cp.ink) { Task { await monitor.next() } }
                    icon(liked ? "heart.fill" : "heart", liked ? wAccent : cp.inkSoft) { liked.toggle() }
                }
            }
            .padding(.top, 6)

            // album (fixed 2-line height)
            Text(info.album)
                .font(theme.font(.caption)).foregroundColor(cp.inkSoft)
                .lineLimit(2).frame(height: 27, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)

            // footer: music mark + faux scan bars
            HStack(spacing: 9) {
                Image(systemName: "music.note").font(.system(size: 16)).foregroundColor(cp.ink)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array([6, 12, 4, 16, 9, 14, 5, 11, 17, 7, 13, 4, 10, 15, 6, 12, 8].enumerated()), id: \.offset) { _, h in
                        Rectangle().fill(cp.ink).frame(width: 2, height: CGFloat(h)).opacity(0.85)
                    }
                }
                .frame(height: 18)
            }
            .padding(.top, 12)
        }
        .frame(width: Poster.artW)
        .themedCard(theme, fill: cp.paper,
                    insets: .init(top: 12, leading: 12, bottom: 11, trailing: 12))
        .task(id: info.art) {
            let b64 = info.art
            art = decodeArtwork(b64)                 // cheap decode, fine on main
            // heavy 56×56 quantise off the main actor so it never janks the UI
            cover = await Task.detached {
                decodeArtwork(b64).flatMap { CoverPalette.extract($0) } ?? .fallback
            }.value
        }
        .onChange(of: info.art) { _, _ in liked = false }   // clear like on track change
    }

    private func coverImage(_ cp: CoverPalette) -> some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                cp.frame
            }
        }
        .frame(width: Poster.artW, height: Poster.artW)
        .themedMedia(theme, border: cp.frame, lineWidth: 4)
    }

    private func icon(_ name: String, _ color: Color, _ action: (() -> Void)? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundColor(color)
            .padding(3)
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    private func togglePlay() {
        Task { await monitor.togglePlayPause() }
        override.flip(to: !shownPlaying)
    }
}
