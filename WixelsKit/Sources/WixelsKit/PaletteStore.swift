// PaletteStore — watches the wal colors.json and republishes it live. Lives in
// WixelsKit (public) because the erased WidgetView observes it across the plugin
// ABI; the host constructs the single instance and injects it.
//
// It hides file-watching, pywal's in-place rewrite, JSON parsing, and sparse
// palette layering behind `@Published var palette`.

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

    // WIXELS_COLORS replaces only the configured file path.
    private let file: String
    private let overrides: PaletteOverrides
    private var fileOverrides = PaletteOverrides()
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?

    public init(colorsPath: String? = nil, overrides: PaletteOverrides = .init()) {
        self.overrides = overrides
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
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let special = obj["special"] as? [String: Any] ?? [:]
        let colors = obj["colors"] as? [String: Any] ?? [:]

        fileOverrides = PaletteOverrides(background: fileColor(special, key: "background"),
                                        foreground: fileColor(special, key: "foreground"),
                                        accents: (0..<16).map { fileColor(colors, key: "color\($0)") })
        let new = overrides.applying(to: fileOverrides.applying(to: .fallback))
        if new != palette { palette = new; reloadCount += 1 }
    }

    /// Themed widgets get their own default palette for values their selected file
    /// and TOML configuration leave unspecified. Legacy widgets retain `.palette`.
    public func resolvedPalette(for theme: ThemeDefinition) -> Palette {
        overrides.applying(to: fileOverrides.applying(to: theme.defaultPalette))
    }

    private func fileColor(_ table: [String: Any], key: String) -> RGB? {
        guard let value = table[key] else { return nil }
        guard let hex = value as? String, let rgb = RGB(hex: hex) else {
            Log.note("invalid color value '\(key)' in \(file) — ignoring")
            return nil
        }
        return rgb
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

    /// Tear down the file/directory watchers. Called when the owning host is replaced
    /// (live config reload) so the retired store's DispatchSource is released
    /// deterministically instead of lingering until dealloc.
    public func stop() {
        source?.cancel(); source = nil
        directorySource?.cancel(); directorySource = nil
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
