// Desktop — your layout. THIS is the one file to edit to arrange wixels.
//
// Each `.on("kind")` enables a widget at its catalog-default placement (defined in
// that widget's `spec`, see Widgets/*.swift). To move or resize one, pass `at:`
// with a Placement override. To disable one, delete or comment its line.
//
// Order matters when two widgets share a window level: a later line stacks in
// front. The frog is listed before the clock so the clock hides the frog's body.
//
// Unknown kinds are ignored, so a typo just means that widget doesn't appear.

import Foundation

@MainActor
func desktopConfig() -> [DesktopEntry] {
    [
        .on("sys"),
        .on("nowplaying"),
        .on("disk-snail"),
        .on("pet"),
        .on("plant"),
        .on("quotes"),
        .on("frog"),          // before clock: clock orders in front, hides frog body
        .on("clock"),
        .on("stats"),
        .on("owl"),
        .on("weather"),
        .on("poster"),

        // Example override — move stats to the bottom-left instead:
        // .on("stats", at: .init(anchor: .bottomLeft, offset: .init(width: 20, height: 36),
        //                        size: .init(width: 220, height: 150), align: .leading)),
    ]
}
