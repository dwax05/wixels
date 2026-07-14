// Plugin entry point. The host dlopens this dylib and calls `wixels_register` by
// its C symbol name (a mangled Swift symbol wouldn't be a stable dlsym contract),
// passing an opaque pointer to its Registrar. We register this plugin's widget
// spec(s). Both sides share the one dynamic WixelsKit, so the Registrar pointer +
// the WidgetSpec types have a single identity across the dlopen boundary.

import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ ctx: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>.fromOpaque(ctx).takeUnretainedValue()
    registrar.add(PixelClock.spec())
}
