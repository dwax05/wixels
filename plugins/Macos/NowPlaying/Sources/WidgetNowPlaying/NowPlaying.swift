import AppKit
import SwiftUI
import WixelsKit
struct NativeNowPlaying: ThemeableWixel {
 let monitor: MusicMonitor; static let kind = "nowplaying"; static let refresh: RefreshPolicy = .interval(3); static let interactive = true
 static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .bottomLeft, offset: .init(width: 28, height: 32), size: .init(width: 300, height: 102), sizing: .fitContent), previews: [.init("Playing", sample: .init(hasTrack: true, title: "A Kind of Magic", artist: "Queen", playing: true, art: "")), .init("Empty", sample: .idle)]) { s, _ in .init(monitor: s.music) } }
 func sample() async -> NowPlayingInfo { await monitor.nowPlaying() }
 func render(_ s: NowPlayingInfo, _ theme: ThemeContext) -> some View { NativeNowPlayingView(info: s, theme: theme, toggle: { await monitor.togglePlayPause() }) }
}
private struct NativeNowPlayingView: View {
 let info: NowPlayingInfo; let theme: ThemeContext; let toggle: @Sendable () async -> Void
 @State private var art: NSImage?
 var body: some View { NativeCard(theme: theme) { HStack(spacing: 12) { Group { if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) } else { Image(systemName: "music.note").font(.title).foregroundStyle(theme.color(.secondary)) } }.frame(width: 58, height: 58).themedMedia(theme, border: theme.color(.border), lineWidth: 0.5); VStack(alignment: .leading, spacing: 4) { NativeHeader("Now Playing", symbol: info.playing ? "speaker.wave.2" : "pause.circle", theme: theme); Text(info.hasTrack ? info.title : "Nothing playing").font(theme.font(.body)).foregroundStyle(theme.color(.foreground)).lineLimit(1); Text(info.hasTrack ? info.artist : "Choose something to play").font(theme.font(.label)).foregroundStyle(theme.color(.secondary)).lineLimit(1) }; Spacer(minLength: 0) } }.contentShape(theme.tokens.card.shape).onTapGesture { guard info.hasTrack else { return }; Task { await toggle() } }.task(id: info.art) { art = Data(base64Encoded: info.art).flatMap(NSImage.init(data:)) }.accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityLabel(info.hasTrack ? "\(info.title) by \(info.artist). Toggle playback" : "Nothing playing") }
}
