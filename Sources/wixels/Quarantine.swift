// Quarantine — first-run consent for user-installed extension files.
//
// Extension packs are downloaded ZIPs, so every dylib copied into
// ~/.config/wixels carries the com.apple.quarantine attribute and Gatekeeper
// blocks dlopen of unnotarized quarantined code. The files belong to the user,
// so the attribute can be removed in-process with removexattr — no shell, no
// privileges. We ask once at launch, before any dlopen; declined files are
// excluded from loading rather than left to fail inside Gatekeeper.

import AppKit
import Foundation
import WixelsKit

enum Quarantine {
    private static let attribute = "com.apple.quarantine"

    /// Paths under the given directories that are loadable extensions still
    /// carrying the download quarantine attribute.
    static func flaggedExtensions(in directories: [String]) -> [String] {
        directories.flatMap { dir in
            PluginLoader.loadableFiles(in: dir).map { URL(fileURLWithPath: dir).appendingPathComponent($0).path }
        }.filter(isFlagged)
    }

    static func isFlagged(_ path: String) -> Bool {
        getxattr(path, attribute, nil, 0, 0, 0) >= 0
    }

    /// Removes the quarantine attribute from each path. Returns the paths that
    /// could not be cleared.
    static func strip(_ paths: [String]) -> [String] {
        paths.filter { removexattr($0, attribute, 0) != 0 }
    }

    /// Scans the user extension directories and, when quarantined files exist,
    /// asks once for consent to clear them. Returns the paths that must be
    /// excluded from loading (declined or failed to clear).
    @MainActor
    static func resolveUserExtensions() -> Set<String> {
        let user = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/wixels")
        let flagged = flaggedExtensions(in: [user.appendingPathComponent("plugins").path,
                                             user.appendingPathComponent("themes").path])
        guard !flagged.isEmpty else { return [] }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow downloaded extensions?"
        alert.informativeText = """
            \(flagged.count) extension file(s) in ~/.config/wixels were downloaded from \
            the internet, so macOS quarantines them and Wixels cannot load them.

            Extensions run as trusted code inside Wixels. Only continue if they came \
            from a source you trust, such as a Wixels GitHub release.
            """
        alert.addButton(withTitle: "Remove Quarantine and Load")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            Log.note("quarantined extensions skipped — \(flagged.count) file(s) not loaded")
            return Set(flagged)
        }

        let failed = strip(flagged)
        if failed.isEmpty {
            Log.note("removed quarantine from \(flagged.count) extension file(s)")
        } else {
            Log.note("could not remove quarantine from: \(failed.joined(separator: ", "))")
        }
        return Set(failed)
    }
}
