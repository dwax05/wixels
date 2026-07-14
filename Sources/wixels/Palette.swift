// Palette — the wal colors.json, parsed and republished live.
//
// One source (wal colors.json), so this is NOT a seam — but its interface is
// deep: it hides file-watching, pywal's in-place rewrite, JSON parsing, and
// publishing behind `@Published var palette`.
//
// Colours are kept as RGB (0…255 components), not SwiftUI Color, so widgets can
// derive shades with `mix`/`shade` exactly like the Übersicht widgets' hex
// helpers. `.color` bridges to SwiftUI at draw time.

import SwiftUI
import Combine

struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double   // 0…255

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF); g = Double((v >> 8) & 0xFF); b = Double(v & 0xFF)
    }

    var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    /// Linear interpolate toward `o` by `t` (0…1) — the JS `mix(a,b,t)`.
    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    /// Multiply each channel by `f` (darken <1 / lighten >1) — the JS `shade(a,f)`.
    func shade(_ f: Double) -> RGB { RGB(r * f, g * f, b * f) }

    /// Non-failable hex parse for hardcoded literals — falls back to neutral grey
    /// instead of trapping if a constant is ever mistyped.
    static func from(_ hex: String) -> RGB { RGB(hex: hex) ?? RGB(120, 120, 120) }
}

struct Palette: Equatable, Sendable {
    var background: RGB
    var foreground: RGB
    var accents: [RGB]          // color0…15

    /// color-N with clamping (the JS reads `c.colorN` with `||` fallbacks).
    func c(_ i: Int) -> RGB { accents[max(0, min(accents.count - 1, i))] }

    static let fallback = Palette(
        background: RGB(10, 25, 25), foreground: RGB(193, 197, 197),
        accents: (0..<16).map { _ in RGB(120, 120, 120) }
    )
}

/// @unchecked Sendable: every access is on the main thread (init on main, and
/// the DispatchSource fires on the .main queue). We deliberately avoid Swift
/// Concurrency in the watcher — touching MainActor/Task/assumeIsolated inside a
/// DispatchSource handler trips `swift_task_isCurrentExecutor` ->
/// `dispatch_assert_queue` (abort) on Swift 6.
final class PaletteStore: ObservableObject, @unchecked Sendable {
    @Published var palette: Palette = .fallback
    @Published var reloadCount = 0

    // WIXELS_COLORS overrides the watched palette file (isolated tests).
    private let file = ProcessInfo.processInfo.environment["WIXELS_COLORS"]
        ?? ("~/.cache/wal/colors.json" as NSString).expandingTildeInPath
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init() {
        reload()
        watch()
    }

    private func reload() {
        // @unchecked Sendable rests on every mutation being on main. init() and the
        // DispatchSource both call this on .main; assert it so an off-main construction
        // fails loudly instead of silently racing @Published.
        dispatchPrecondition(condition: .onQueue(.main))
        guard
            let data = FileManager.default.contents(atPath: file),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let special = obj["special"] as? [String: String],
            let colors = obj["colors"] as? [String: String]
        else { return }

        let accents = (0..<16).map { RGB(hex: colors["color\($0)"] ?? "") ?? RGB(120, 120, 120) }
        let new = Palette(
            background: RGB(hex: special["background"] ?? "") ?? Palette.fallback.background,
            foreground: RGB(hex: special["foreground"] ?? "") ?? Palette.fallback.foreground,
            accents: accents
        )
        if new != palette { palette = new; reloadCount += 1 }
    }

    /// Watch the *file* fd: pywal rewrites colors.json in place (truncate+write,
    /// same inode), so a directory watch never fires. `.write`/`.extend` catch
    /// the in-place rewrite; `.delete`/`.rename` mean the file was replaced, so
    /// we tear down and re-arm on the new inode.
    private func watch() {
        source?.cancel()
        fd = open(file, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.watch()
            }
            return
        }
        // Fire on the MAIN queue: handler runs on the main thread (correct for
        // mutating @Published) using only plain Dispatch closures — no Swift
        // Concurrency, so no executor assertion.
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let replaced = src.data.contains(.delete) || src.data.contains(.rename)
            // debounce: pywal writes the file in a couple of steps
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.reload()
                if replaced { self.watch() }   // file replaced → re-arm on new inode
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
    }
}
