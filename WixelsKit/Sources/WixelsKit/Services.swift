// Services — the shared samplers a widget spec may need. The design's single-
// sampler rule: one CPUSource feeds both the pet and the stats card, one
// MusicMonitor feeds the pet, now-playing, and poster — not one reader each.
// The host passes this to each `spec.build(services, options)`, so widgets that
// share a source pull the same instance instead of constructing their own.
//
// lazy: a source is only built if some enabled widget actually asks for it.

import Foundation

@MainActor
public final class Services {
    private let nowplayingPath: String?
    public lazy var music = MusicMonitor(cachePath: nowplayingPath)   // pet + now-playing + poster
    public lazy var cpu = CPUSource()                                 // pet + stats

    /// `nowplayingPath` comes from the config's `[paths]` (nil = MusicMonitor's default).
    public init(nowplayingPath: String? = nil) { self.nowplayingPath = nowplayingPath }
}
