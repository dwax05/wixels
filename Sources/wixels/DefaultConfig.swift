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
    # enabled = false to hide it while retaining its settings. Placement fields are optional — omit them to use the
    # widget's built-in default. Order = mount order = z-stacking among widgets that
    # share a window level (the frog is before the clock so the clock hides its body).
    #
    # Placement fields:  anchor  offset=[x,y]  size=[w,h]  zBoost  align
    # anchors: topLeft topRight bottomLeft bottomRight center topCenter
    # A [widget.options] table passes per-widget settings (e.g. disk-snail path).

    # App-global data files. Env vars WIXELS_COLORS / WIXELS_NOWPLAYING override these.
    [paths]
    colors     = "~/.cache/wal/colors.json"        # pywal palette — recolours everything
    nowplaying = "~/.cache/wixels/nowplaying.json" # music cache your publisher writes

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

    # Example override — move stats to the bottom-left instead:
    # [[widget]]
    # kind = "stats"
    # anchor = "bottomLeft"
    # offset = [20, 36]
    # size = [220, 164]
    # align = "leading"
    """
}
