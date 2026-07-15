// NowPlaying — port of cynaberii-nowplaying: a pixel cassette showing album art,
// two reels, and the current title/artist/state. Click toggles play/pause with an
// optimistic flip (like the JS override) until the next poll reads the real state.
//
// Track data (incl. base64 album art) comes from MusicMonitor's embedded
// MediaRemote adapter, which reads the active system media session directly.

import AppKit
import SwiftUI
import WixelsKit

struct NowPlaying: ThemeableWixel {
    let monitor: MusicMonitor

    static let kind = "nowplaying"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomLeft, offset: .init(width: 12, height: 36),
                                    size: .init(width: 320, height: 96)),
            build: { s, _ in NowPlaying(monitor: s.music) })
    }
    static let refresh: RefreshPolicy = .interval(3)
    static let interactive = true

    func sample() async -> NowPlayingInfo { await monitor.nowPlaying() }

    func render(_ sample: NowPlayingInfo, _ theme: ThemeContext) -> some View {
        NowPlayingView(info: sample, theme: theme, actions: NowPlayingActions { await monitor.togglePlayPause() })
    }
}

struct NowPlayingView: View {
    let info: NowPlayingInfo
    let theme: ThemeContext
    let actions: NowPlayingActions

    @State private var art: NSImage?
    @State private var override = PlayOverride()

    // shown play-state = optimistic override (if still fresh) else the real poll
    private var shownPlaying: Bool {
        info.hasTrack ? override.resolve(info.playing) : false
    }

    var body: some View {
        let accent = theme.color(.accent), accent2 = theme.color(.alternateAccent)
        let sage = theme.color(.secondary), ink = theme.color(.foreground)

        HStack(alignment: .center, spacing: 12) {
            artwork(sage: sage)
            reels(accent: accent, accent2: accent2)
            VStack(alignment: .leading, spacing: 5) {
                Text(info.hasTrack ? info.title : "nothing playing")
                    .font(theme.font(.body))
                    .foregroundColor(ink).lineLimit(1).truncationMode(.tail)
                Text(info.hasTrack ? info.artist : "—")
                    .font(theme.font(.label))
                    .foregroundColor(accent).lineLimit(1).truncationMode(.tail)
                Text(!info.hasTrack ? "❚❚ idle" : shownPlaying ? "▶ playing" : "❚❚ paused")
                    .font(theme.font(.caption))
                    .foregroundColor(sage)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 272, alignment: .leading)            // stable right edge (JS fixed width)
        .themedCard(theme)
        .contentShape(theme.tokens.card.shape)
        .onTapGesture { toggle() }
        .task(id: info.art) { art = decodeArtwork(info.art) }
    }

    @ViewBuilder private func artwork(sage: Color) -> some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().interpolation(.none)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text("♪").font(theme.font(.symbol)).foregroundColor(sage)
            }
        }
        .frame(width: 56, height: 56)
        .themedMedia(theme, border: sage, lineWidth: 3)
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
        Task { await actions.togglePlayPause() }
        override.flip(to: !shownPlaying)
    }
}
