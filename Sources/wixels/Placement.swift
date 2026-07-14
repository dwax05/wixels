// Placement — where a widget's window sits. DESIGN.md calls this "a plain struct,
// not a seam": the host owns screen coordinates, a widget never does, and a config
// only ever hands the host one of these. Mirrors the params `WidgetHost.mount`
// already took, gathered into one value so a spec (default) and a Desktop entry
// (override) can pass placement around as data.

import SwiftUI

struct Placement {
    var anchor: Anchor
    var offset: CGSize = .zero
    var size: CGSize = .init(width: 150, height: 70)
    var zBoost: Int = 0          // nudge window level above peers (e.g. clock over frog)
    var align: Alignment? = nil  // pin content to a window edge (else centered)
}
