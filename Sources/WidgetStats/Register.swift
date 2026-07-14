// Plugin entry point — see WidgetClock/Register.swift for the mechanism.

import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ ctx: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>.fromOpaque(ctx).takeUnretainedValue()
    registrar.add(Stats.spec())
}
