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
    # This host-only beta does not include widgets. Install the matching
    # Wixels-Cynaberii extension pack into ~/.config/wixels/, then restart Wixels.
    # Until then, the entries below are harmless and appear as unavailable in logs.

    # Optional palette. WIXELS_COLORS replaces only `file`; individual values below
    # always win. Omit any value to use the pywal file, then the selected theme default.
    [colors]
    file = "~/.cache/wal/colors.json"
    # background = "#102021"
    # foreground = "F3E9D2"
    # color0 = "#1A2C2D" # color1 through color15 are also supported

    [[widget]]
    kind = "sys"

    [[widget]]
    kind = "nowplaying"

    [[widget]]
    kind = "disk-snail"
      [widget.options]
      path = "/"                 # volume the shell gauge measures

    [[widget]]
    kind = "pet"

    [[widget]]
    kind = "plant"

    [[widget]]
    kind = "quotes"
      [widget.options]
      path = "~/.config/wixels/quotes.json"   # JSON array of quote strings

    [[widget]]
    kind = "frog"                # before clock: clock orders in front, hides frog body

    [[widget]]
    kind = "clock"

    [[widget]]
    kind = "stats"

    [[widget]]
    kind = "owl"

    [[widget]]
    kind = "weather"

    [[widget]]
    kind = "poster"

    # Legacy placement example (migrated automatically on its first layout save):
    # [[widget]]
    # kind = "stats"
    # anchor = "bottomLeft"
    # offset = [20, 36]
    # size = [220, 164]
    # align = "leading"
    """
}
