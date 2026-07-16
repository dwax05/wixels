import AppKit
import SwiftUI
import WixelsKit
import MacosWidgetPresentation

struct NativePoster: ThemeableWixel {
    let monitor: MusicMonitor

    static let kind = "poster"
    static let refresh: RefreshPolicy = .interval(4)
    static let interactive = true

    static func spec() -> ThemedWidgetSpec {
        .init(widget: Self.self,
              defaultPlacement: .init(anchor: .topRight, offset: .init(width: -24, height: -210),
                                      size: .init(width: 260, height: 410), align: .topTrailing, sizing: .fitContent),
              previews: [
                .init("Playing", sample: .init(hasTrack: true, title: "A Kind of Magic", artist: "Queen",
                    album: "A Kind of Magic", duration: "4:24", playing: true, art: "")),
                .init("Empty", sample: .idle),
              ]) { services, _ in Self(monitor: services.music) }
    }

    func sample() async -> PosterInfo { await monitor.poster() }
    func render(_ sample: PosterInfo, _ theme: ThemeContext) -> some View {
        NativePosterView(info: sample, theme: theme,
            toggle: { await monitor.togglePlayPause() }, next: { await monitor.next() },
            shuffle: { await monitor.toggleShuffle() })
    }
}

private struct NativePosterView: View {
    let info: PosterInfo
    let theme: ThemeContext
    let toggle: @Sendable () async -> Void
    let next: @Sendable () async -> Void
    let shuffle: @Sendable () async -> Void

    @State private var art: NSImage?
    @State private var override = PlayOverride()
    @State private var shuffleOn = false

    private var shownPlaying: Bool { override.resolve(info.playing) }

    var body: some View {
        NativeCard(theme: theme) {
            if info.hasTrack {
                VStack(alignment: .leading, spacing: 12) {
                    NativeHeader("Now Playing", symbol: "music.note", theme: theme)
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.title).font(theme.font(.title)).foregroundStyle(theme.color(.foreground))
                            .lineLimit(2)
                        Text(info.artist).font(theme.font(.body)).foregroundStyle(theme.color(.secondary)).lineLimit(1)
                        Text(info.album).font(theme.font(.label)).foregroundStyle(theme.color(.muted)).lineLimit(1)
                    }
                    controls
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    NativeHeader("Now Playing", symbol: "music.note", theme: theme)
                    NativeStateView(.empty, message: "Nothing playing", theme: theme)
                }
            }
        }
        .task(id: info.art) { art = decodeArtwork(info.art) }
    }

    private var artwork: some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note.list").font(.system(size: 42))
                    .foregroundStyle(theme.color(.secondary))
            }
        }
        .frame(width: 228, height: 228)
        .background(theme.color(.background).opacity(0.35))
        .themedMedia(theme, border: theme.color(.border), lineWidth: 0.5)
        .accessibilityLabel("Album artwork")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { Task { await shuffle(); shuffleOn.toggle() } } label: {
                Image(systemName: "shuffle").foregroundStyle(shuffleOn ? theme.color(.accent) : theme.color(.secondary))
            }
            Spacer()
            Button { togglePlayback() } label: {
                Image(systemName: shownPlaying ? "pause.fill" : "play.fill").font(.system(size: 19))
                    .frame(width: 32, height: 28).foregroundStyle(theme.color(.accent))
            }
            Button { Task { await next() } } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.foreground))
        .accessibilityElement(children: .contain)
    }

    private func togglePlayback() {
        Task { await toggle() }
        override.flip(to: !shownPlaying)
    }
}
