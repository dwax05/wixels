// Placement — where a widget's window sits. A plain struct, not a seam: the host
// owns screen coordinates, a widget never does, and config/spec hand the host one
// of these. Public because it crosses the plugin ABI (specs + config build them).

import SwiftUI

public enum Anchor: String, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight, center, topCenter
}

/// Whether a placement owns a fixed window or lets its rendered content determine it.
/// `.fixed` preserves the historic behavior. `.fitContent` uses `size` until the
/// first render can be measured, then the host keeps the window tightly fitted.
public enum PlacementSizing: Sendable {
    case fixed
    case fitContent
}

public struct Placement: Sendable {
    public var anchor: Anchor
    public var offset: CGSize
    public var size: CGSize
    public var zBoost: Int          // nudge window level above peers (e.g. clock over frog)
    public var align: Alignment?    // pin content to a window edge (else centered)
    public var sizing: PlacementSizing

    public init(anchor: Anchor, offset: CGSize = .zero,
                size: CGSize = .init(width: 150, height: 70),
                zBoost: Int = 0, align: Alignment? = nil,
                sizing: PlacementSizing = .fixed) {
        self.anchor = anchor; self.offset = offset; self.size = size
        self.zBoost = zBoost; self.align = align; self.sizing = sizing
    }
}
