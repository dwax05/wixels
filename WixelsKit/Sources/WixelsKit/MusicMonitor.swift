// MusicMonitor — is a song playing right now?
//
// NOTE: macOS 15.4+ gates the private MediaRemote now-playing API — an
// untrusted (ad-hoc-signed) binary like ours gets nil back from
// MRMediaRemoteGetNowPlayingInfo, even though the Apple-signed `swift`
// interpreter and `nowplaying-cli`'s bundled MediaRemoteMini shim get real data.
// Reimplementing that shim in-process isn't worth it.
//
// Instead we read a shared cache an external publisher writes: a sketchybar plugin
// runs ONE nowplaying-cli stream and publishes ~/.cache/wixels/nowplaying.json
// (event-driven + 3s poll; override the path with WIXELS_NOWPLAYING). We read
// `playbackRate` from it — no per-tick spawn, and consistent with the bar and
// the other widgets. If the cache is missing/stale, fall back to a direct
// `nowplaying-cli get playbackRate` (which works where in-process MediaRemote
// does not).

import Foundation

/// The full current-track snapshot the now-playing widget draws. `art` is raw
/// base64 (the shared cache stores it un-prefixed), "" when there's no artwork.
public struct NowPlayingInfo: Equatable, Sendable {
    public var hasTrack: Bool
    public var title: String
    public var artist: String
    public var playing: Bool
    public var art: String

    public init(hasTrack: Bool, title: String, artist: String, playing: Bool, art: String) {
        self.hasTrack = hasTrack; self.title = title; self.artist = artist
        self.playing = playing; self.art = art
    }

    public static let idle = NowPlayingInfo(hasTrack: false, title: "", artist: "", playing: false, art: "")
}

/// The richer snapshot the poster card draws — adds album + formatted duration.
public struct PosterInfo: Equatable, Sendable {
    public var hasTrack: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var duration: String     // m:ss
    public var playing: Bool
    public var art: String          // raw base64

    public init(hasTrack: Bool, title: String, artist: String, album: String,
                duration: String, playing: Bool, art: String) {
        self.hasTrack = hasTrack; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.playing = playing; self.art = art
    }

    public static let idle = PosterInfo(hasTrack: false, title: "", artist: "", album: "",
                                 duration: "", playing: false, art: "")
}

/// Optimistic play/pause flip: a click flips the shown state immediately and holds
/// it for a few seconds until the next poll reads the real state. Shared by the
/// cassette (NowPlaying) and poster cards.
public struct PlayOverride {
    private var pending: (playing: Bool, until: Date)?

    public init() {}

    public mutating func flip(to playing: Bool, for seconds: TimeInterval = 3.5) {
        pending = (playing, Date().addingTimeInterval(seconds))
    }

    /// The shown state: the pending flip while it's still fresh, else the real poll.
    public func resolve(_ real: Bool) -> Bool {
        if let p = pending, Date() < p.until { return p.playing }
        return real
    }
}

public final class MusicMonitor: @unchecked Sendable {
    // Cache file the external publisher writes. Precedence: WIXELS_NOWPLAYING env >
    // the config's `[paths]` nowplaying (passed via Services) > the default.
    private let cache: String
    private let staleSeconds: TimeInterval = 30
    private let npCLI = "/opt/homebrew/bin/nowplaying-cli"

    public init(cachePath: String? = nil) {
        cache = Paths.resolve(env: "WIXELS_NOWPLAYING", config: cachePath,
                              default: "~/.cache/wixels/nowplaying.json")
    }

    /// True when something is actively playing (playbackRate > 0).
    public func isPlayingNow() async -> Bool {
        if let d = cacheDict() { return rate(d["playbackRate"]) > 0 }
        return (Double(runNP(["get", "playbackRate"]).first ?? "") ?? 0) > 0
    }

    /// Full track snapshot for the now-playing widget: shared cache first (has art
    /// + all fields), falling back to a direct `nowplaying-cli get` trio (no art)
    /// when the bar isn't publishing.
    public func nowPlaying() async -> NowPlayingInfo {
        if let d = cacheDict() {
            let title = string(d["title"])
            return NowPlayingInfo(
                hasTrack: !title.isEmpty, title: title, artist: string(d["artist"]),
                playing: rate(d["playbackRate"]) > 0, art: (d["art"] as? String) ?? "")
        }
        let out = runNP(["get", "title", "artist", "playbackRate"])
        let title = out.indices.contains(0) ? clean(out[0]) : ""
        let artist = out.indices.contains(1) ? clean(out[1]) : ""
        let playing = (out.indices.contains(2) ? Double(out[2]) ?? 0 : 0) > 0
        return NowPlayingInfo(hasTrack: !title.isEmpty, title: title, artist: artist,
                              playing: playing, art: "")
    }

    /// Full poster snapshot: cache first (has album/duration/art), CLI fallback.
    public func poster() async -> PosterInfo {
        if let d = cacheDict() {
            let title = string(d["title"])
            return PosterInfo(
                hasTrack: !title.isEmpty, title: title, artist: string(d["artist"]),
                album: string(d["album"]), duration: Self.fmtTime(string(d["duration"])),
                playing: rate(d["playbackRate"]) > 0, art: (d["art"] as? String) ?? "")
        }
        let out = runNP(["get", "title", "artist", "album", "duration", "playbackRate"])
        func at(_ i: Int) -> String { out.indices.contains(i) ? clean(out[i]) : "" }
        let title = at(0)
        return PosterInfo(hasTrack: !title.isEmpty, title: title, artist: at(1), album: at(2),
                          duration: Self.fmtTime(at(3)), playing: (Double(at(4)) ?? 0) > 0, art: "")
    }

    /// Toggle play/pause (click action). MediaRemote's writes still work for an
    /// untrusted binary even though its now-playing *reads* are gated (see header).
    public func togglePlayPause() { _ = runNP(["togglePlayPause"]) }

    /// Skip to the next track.
    public func next() { _ = runNP(["next"]) }

    /// Toggle Spotify shuffle over AppleScript (harmless no-op if Spotify isn't the player).
    public func toggleShuffle() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"Spotify\" to set shuffling to not shuffling"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Seconds string → "m:ss" (or "" when zero/unparseable).
    private static func fmtTime(_ s: String) -> String {
        guard let secs = Double(s), secs > 0 else { return "" }
        let t = Int(secs)
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /// The shared cache as a dict, or nil if missing/stale/unreadable.
    private func cacheDict() -> [String: Any]? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cache),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) <= staleSeconds,
              let data = FileManager.default.contents(atPath: cache),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// playbackRate may arrive as a number or a string ("1") — normalise to Double.
    private func rate(_ v: Any?) -> Double {
        if let n = v as? Double { return n }
        if let s = v as? String { return Double(s) ?? 0 }
        if let n = v as? Int { return Double(n) }
        return 0
    }

    private func string(_ v: Any?) -> String { clean(v as? String ?? "") }
    private func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t == "null" ? "" : t
    }

    /// Spawn `nowplaying-cli <args>` and return stdout lines (empty on failure).
    /// Used only for the fallback path and the toggle action — not per-tick when
    /// the shared cache is live.
    private func runNP(_ args: [String]) -> [String] {
        guard FileManager.default.isExecutableFile(atPath: npCLI) else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: npCLI)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
