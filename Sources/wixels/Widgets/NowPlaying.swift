// NowPlaying — port of cynaberii-nowplaying: a pixel cassette showing album art,
// two reels, and the current title/artist/state. Click toggles play/pause with an
// optimistic flip (like the JS override) until the next poll reads the real state.
//
// Track data (incl. base64 album art) comes from MusicMonitor, which reads the
// shared ~/.cache/cynaberii/nowplaying.json the sketchybar music plugin publishes
// — the same exposed file the Übersicht widget's np.py read.

import AppKit
import SwiftUI

/// Decode raw base64 artwork into an image (nil when absent/undecodable). Shared by
/// the cassette + poster cards.
func decodeArtwork(_ b64: String) -> NSImage? {
    guard !b64.isEmpty,
          let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    else { return nil }
    return NSImage(data: data)
}

struct NowPlaying: Widget {
    let monitor: MusicMonitor

    static let kind = "nowplaying"
    static let refresh: RefreshPolicy = .interval(3)
    static let interactive = true

    func sample() async -> NowPlayingInfo { await monitor.nowPlaying() }

    func render(_ s: NowPlayingInfo, _ p: Palette) -> some View {
        NowPlayingView(info: s, p: p, monitor: monitor)
    }
}

private struct NowPlayingView: View {
    let info: NowPlayingInfo
    let p: Palette
    let monitor: MusicMonitor

    @State private var art: NSImage?
    @State private var override = PlayOverride()

    // shown play-state = optimistic override (if still fresh) else the real poll
    private var shownPlaying: Bool {
        info.hasTrack ? override.resolve(info.playing) : false
    }

    var body: some View {
        let accent = p.c(4).color, accent2 = p.c(3).color
        let sage = p.c(6).color, ink = p.foreground.color

        HStack(alignment: .center, spacing: 12) {
            artwork(sage: sage)
            reels(accent: accent, accent2: accent2)
            VStack(alignment: .leading, spacing: 5) {
                Text(info.hasTrack ? info.title : "nothing playing")
                    .font(.pixel(11))
                    .foregroundColor(ink).lineLimit(1).truncationMode(.tail)
                Text(info.hasTrack ? info.artist : "—")
                    .font(.pixel(9))
                    .foregroundColor(accent).lineLimit(1).truncationMode(.tail)
                Text(!info.hasTrack ? "❚❚ idle" : shownPlaying ? "▶ playing" : "❚❚ paused")
                    .font(.pixel(8))
                    .foregroundColor(sage)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 272, alignment: .leading)            // stable right edge (JS fixed width)
        .pane(p)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .task(id: info.art) { art = decodeArtwork(info.art) }
    }

    @ViewBuilder private func artwork(sage: Color) -> some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().interpolation(.none)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text("♪").font(.pixel(22)).foregroundColor(sage)
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .overlay(Rectangle().strokeBorder(sage, lineWidth: 3))
    }

    // two static cassette reels
    private func reels(accent: Color, accent2: Color) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { _ in
                ZStack {
                    Circle().strokeBorder(accent, lineWidth: 3)
                    Circle().strokeBorder(accent2, lineWidth: 2).padding(3)
                }
                .frame(width: 18, height: 18)
            }
        }
    }

    private func toggle() {
        guard info.hasTrack else { return }
        monitor.togglePlayPause()
        override.flip(to: !shownPlaying)
    }
}
