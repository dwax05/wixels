// The default desktop layout, written to ~/.config/wixels/desktop.toml on first
// run and used in-memory if the file is ever missing/unreadable. Lists every
// built-in widget in its default position — editing this file (or the one on disk)
// is how you rearrange wixels without recompiling.

import Foundation
import WixelsKit

extension Config {
    /// Scaffold the config file on first run so there's something to edit.
    static func writeDefaultIfMissing() {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if (try? defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)) != nil {
            Log.note("wrote default config to \(path)")
        }
    }

    static let defaultTOML = """
    # wixels desktop layout. Each [[widget]] enables a widget by `kind`; set
    # enabled = false to hide it while retaining its settings. `folder` selects a
    # plugin group; placement lives independently in layouts/<encoded-folder>.toml.
    # Order = mount order = z-stacking among widgets that
    # share a window level (the frog is before the clock so the clock hides its body).
    #
    # A [widget.options] table passes per-widget settings (e.g. disk-snail path).
    #
    # A kind may be namespaced ("macos/poster") when two installed suites register
    # the same kind; a bare kind resolves to the first loaded. Each widget's theme
    # resolves as: this row's `theme` > its folder's bundled theme > [theme] default
    # > macos.
    #
    # This host-only beta does not include widgets. Install any compatible extension
    # pack into ~/.config/wixels/, then add its widget kinds below and restart Wixels.

    # Optional palette. WIXELS_COLORS replaces only `file`; individual values below
    # always win. Omit any value to use the pywal file, then the selected theme default.
    [colors]
    file = "~/.cache/wal/colors.json"
    # background = "#102021"
    # foreground = "F3E9D2"
    # color0 = "#1A2C2D" # color1 through color15 are also supported

    # Example widget (uncomment and replace after installing a pack):
    # [[widget]]
    # kind = "my-widget"
    # theme = "my-theme"          # optional; overrides the pack's bundled theme
    """
}
