// MusicMonitor — shared system-wide now-playing reader.
//
// MediaRemote is a private macOS framework. Starting with macOS 15.4, its
// daemon accepts metadata reads only from entitled clients, so Wixels invokes
// its bundled BSD-licensed MediaRemoteAdapter through Apple's entitled
// /usr/bin/perl. This removes the old cache-file and Homebrew CLI dependency
// while retaining system-wide support for Music, Spotify, browsers, and other
// MediaRemote publishers.

import Foundation

/// The full current-track snapshot the now-playing widget draws. `art` is raw
/// base64, or "" when the publisher has not supplied artwork yet.
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

public struct NowPlayingActions: Sendable {
    public let togglePlayPause: @Sendable () async -> Void
    public init(togglePlayPause: @escaping @Sendable () async -> Void) {
        self.togglePlayPause = togglePlayPause
    }
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

public actor MusicMonitor {
    private struct Snapshot {
        let title: String
        let artist: String
        let album: String
        let duration: String
        let playing: Bool
        let art: String

        static let idle = Snapshot(title: "", artist: "", album: "", duration: "", playing: false, art: "")
    }

    private let adapterScript: URL?
    private let adapterFramework: URL?
    private var cached: (snapshot: Snapshot, sampledAt: Date)?
    private var streamProcess: Process?
    private var streamTask: Task<Void, Never>?
    private var didLogFailure = false

    /// `resourceRoot` is injected by tests; production finds either the source
    /// staging directory (`WIXELS_PLUGIN_ROOT`) or the app bundle's Resources.
    public init(resourceRoot: URL? = nil) {
        let root = resourceRoot
            ?? ProcessInfo.processInfo.environment["WIXELS_PLUGIN_ROOT"].map(URL.init(fileURLWithPath:))
            ?? Bundle.main.resourceURL
        adapterScript = root?.appendingPathComponent("mediaremote-adapter.pl")
        adapterFramework = root?.appendingPathComponent("MediaRemoteAdapter.framework")
    }

    /// True when something is actively playing.
    public func isPlayingNow() -> Bool { snapshot().playing }

    public func nowPlaying() -> NowPlayingInfo {
        let value = snapshot()
        return NowPlayingInfo(hasTrack: !value.title.isEmpty, title: value.title, artist: value.artist,
                              playing: value.playing, art: value.art)
    }

    public func poster() -> PosterInfo {
        let value = snapshot()
        return PosterInfo(hasTrack: !value.title.isEmpty, title: value.title, artist: value.artist,
                          album: value.album, duration: Self.fmtTime(value.duration),
                          playing: value.playing, art: value.art)
    }

    public func togglePlayPause() { send(command: 2) }
    public func next() { send(command: 4) }
    public func toggleShuffle() { send(command: 6) }

    private func snapshot() -> Snapshot {
        startStreamIfNeeded()
        return cached?.snapshot ?? .idle
    }

    /// Keep one adapter process open and receive MediaRemote notifications as they
    /// happen. The old `get` path launched Perl for every widget refresh (roughly
    /// 30 processes/minute with the default desktop); widgets now read this cache.
    private func startStreamIfNeeded() {
        guard streamProcess == nil,
              let script = adapterScript, let framework = adapterFramework,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"),
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path)
        else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Full snapshots avoid diff-merging state in the host. A short debounce
        // collapses the burst of metadata fields most players emit on track change.
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--debounce=200"]
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            logFailure("could not start MediaRemoteAdapter stream: \(error.localizedDescription)")
            return
        }

        streamProcess = process
        ChildReaper.shared.register(process)
        streamTask = Task { [weak self, pipe, weak process] in
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    await self?.acceptStreamLine(line)
                }
            } catch {
                // Process termination closes the pipe; the next widget read starts
                // a replacement stream if the adapter is available again.
            }
            await self?.streamDidEnd(process)
        }
    }

    private func acceptStreamLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["type"] as? String == "data"
        else { return }
        let payload = envelope["payload"] as? [String: Any] ?? [:]
        cached = (Self.decode(payload), Date())
    }

    private func streamDidEnd(_ process: Process?) {
        guard streamProcess === process else { return }
        if let process { ChildReaper.shared.unregister(process) }
        streamProcess = nil
        streamTask = nil
    }

    private static func decode(_ object: [String: Any]) -> Snapshot {
        func text(_ key: String) -> String {
            let value = (object[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value == "null" ? "" : value
        }
        func number(_ key: String) -> Double {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? String { return Double(value) ?? 0 }
            return 0
        }
        let reportedPlaying = object["playing"] as? Bool
        let playing = (reportedPlaying ?? (number("playing") > 0)) || number("playbackRate") > 0
        let value = Snapshot(title: text("title"), artist: text("artist"), album: text("album"),
                             duration: text("duration"), playing: playing, art: text("artworkData"))
        return value
    }

    private func send(command: Int) {
        guard let script = adapterScript, let framework = adapterFramework,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"),
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path)
        else { logFailure("embedded MediaRemoteAdapter resources are missing") ; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "send", String(command)]
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func logFailure(_ message: String) {
        guard !didLogFailure else { return }
        didLogFailure = true
        Log.note("native now-playing unavailable: \(message)")
    }

    private static func fmtTime(_ s: String) -> String {
        guard let secs = Double(s), secs > 0 else { return "" }
        let t = Int(secs)
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    deinit {
        streamTask?.cancel()
        if let process = streamProcess {
            ChildReaper.shared.unregister(process)
            process.terminate()
        }
    }

}
