// Plugin entry point. The host dlopens this dylib and calls `wixels_register` by its
// C symbol name, passing an opaque pointer to its Registrar. Both sides share the one
// dynamic WixelsKit, so the Registrar + WidgetSpec types have a single identity across
// the dlopen boundary.

import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ ctx: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>.fromOpaque(ctx).takeUnretainedValue()
    registrar.add(Frog.spec())
}
