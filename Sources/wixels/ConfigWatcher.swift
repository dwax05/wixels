// ConfigWatcher — watches desktop.toml and fires a callback when it changes, so the
// host can rebuild the widget set live. Modeled directly on WixelsKit's PaletteStore
// file watcher: the same fd-watch + re-arm + parent-directory-fallback shape.
//
// @unchecked Sendable, NOT @MainActor: the DispatchSource fires on the .main queue and
// the handler uses only plain Dispatch. We deliberately keep Swift Concurrency and
// MainActor.assumeIsolated OUT of the DispatchSource event handler itself (it trips
// dispatch_assert_queue -> abort on Swift 6). The @MainActor `onChange` is invoked from
// a *re-dispatched* main-queue block (the debounce), which is a normal runloop item
// where assumeIsolated is safe — the same place PaletteStore does its debounced reload.

import Foundation

final class ConfigWatcher: @unchecked Sendable {
    private let file: String
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    // Events before this instant are ignored — set while wixels writes the file itself
    // (menu-bar drag-save via Config.writePlacements) so our own writes don't reload.
    private var suspendUntil = Date.distantPast

    init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.file = path
        self.onChange = onChange
        watch()
    }

    /// Run `body` (a config write) without the resulting file event triggering a reload.
    /// The 0.5s window comfortably covers the 0.12s debounce plus the write itself.
    @MainActor
    func ignoringWrites(_ body: () -> Void) {
        suspendUntil = Date().addingTimeInterval(0.5)
        body()
    }

    /// Tear down the watchers. Safe to call more than once.
    func stop() {
        source?.cancel(); source = nil
        directorySource?.cancel(); directorySource = nil
    }

    /// Watch the file fd. `.write`/`.extend` catch an in-place rewrite; `.delete`/`.rename`
    /// mean the file was replaced (editors that save-by-rename), so we re-arm on the new
    /// inode after reloading.
    private func watch() {
        source?.cancel()
        directorySource?.cancel(); directorySource = nil
        fd = open(file, O_EVTONLY)
        guard fd >= 0 else {
            watchParentDirectory()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let replaced = src.data.contains(.delete) || src.data.contains(.rename)
            // debounce: editors write in a couple of steps.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                if replaced { self.watch() }          // re-arm on the new inode
                guard Date() >= self.suspendUntil else { return }   // our own write
                MainActor.assumeIsolated { self.onChange() }
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
    }

    /// If the config dir doesn't exist yet, watch the nearest existing ancestor for the
    /// file's creation without polling, then re-arm on the file fd.
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
            if FileManager.default.fileExists(atPath: self.file) {
                self.watch()
                guard Date() >= self.suspendUntil else { return }
                MainActor.assumeIsolated { self.onChange() }
            } else if FileManager.default.fileExists(atPath: desired) {
                self.watch()
            }
        }
        src.setCancelHandler { close(directoryFD) }
        src.resume(); directorySource = src
    }
}
