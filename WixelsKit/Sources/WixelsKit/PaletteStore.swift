// PaletteStore — watches the wal colors.json and republishes it live. Lives in
// WixelsKit (public) because the erased WidgetView observes it across the plugin
// ABI; the host constructs the single instance and injects it.
//
// One source (wal colors.json), so this is NOT a seam — but its interface is
// deep: it hides file-watching, pywal's in-place rewrite, JSON parsing, and
// publishing behind `@Published var palette`.

import SwiftUI
import Combine

/// @unchecked Sendable: every access is on the main thread (init on main, and
/// the DispatchSource fires on the .main queue). We deliberately avoid Swift
/// Concurrency in the watcher — touching MainActor/Task/assumeIsolated inside a
/// DispatchSource handler trips `swift_task_isCurrentExecutor` ->
/// `dispatch_assert_queue` (abort) on Swift 6.
public final class PaletteStore: ObservableObject, @unchecked Sendable {
    @Published public var palette: Palette = .fallback
    @Published public var reloadCount = 0

    // Watched palette file. Precedence: WIXELS_COLORS env > the config's `[paths]`
    // colors (passed by the host) > the pywal default.
    private let file: String
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?

    public init(colorsPath: String? = nil) {
        file = Paths.resolve(env: "WIXELS_COLORS", config: colorsPath,
                             default: "~/.cache/wal/colors.json")
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
        directorySource?.cancel(); directorySource = nil
        fd = open(file, O_EVTONLY)
        guard fd >= 0 else {
            watchParentDirectory()
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

    /// If pywal has never run, watch for colors.json to be created without polling.
    private func watchParentDirectory() {
        let desired = (file as NSString).deletingLastPathComponent
        var directory = desired
        while !FileManager.default.fileExists(atPath: directory) {
            let parent = (directory as NSString).deletingLastPathComponent
            guard parent != directory else { return }
            directory = parent
        }
        let directoryFD = open(directory, O_EVTONLY)
        guard directoryFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD, eventMask: [.write, .extend, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.file) { self.reload(); self.watch() }
            else if FileManager.default.fileExists(atPath: desired) { self.watch() }
        }
        src.setCancelHandler { close(directoryFD) }
        src.resume(); directorySource = src
    }
}
