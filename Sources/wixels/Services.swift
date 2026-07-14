// Services — the shared samplers a widget spec may need. The design's single-
// sampler rule: one CPUSource feeds both the pet and the stats card, one
// MusicMonitor feeds the pet, now-playing, and poster — not one reader each.
// `catalog(_:)` hands this to every widget's `spec`, so widgets that share a
// source pull the same instance instead of constructing their own.
//
// lazy: a source is only built if some enabled widget actually asks for it.

import Foundation

@MainActor
final class Services {
    lazy var music = MusicMonitor()   // pet + now-playing + poster
    lazy var cpu = CPUSource()        // pet + stats
}
