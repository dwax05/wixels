import WixelsKit
@_cdecl("wixels_register") public func wixels_register(_ context: UnsafeMutableRawPointer) { Unmanaged<Registrar>.fromOpaque(context).takeUnretainedValue().add(NativeNowPlaying.spec()) }
