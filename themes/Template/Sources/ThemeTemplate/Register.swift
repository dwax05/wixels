import WixelsKit

// Copy this package and define one universal aesthetic token set. Themes never
// import widget sample types and cannot replace widget content or placement.
@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>.fromOpaque(context).takeUnretainedValue()
    registrar.add(ThemeDefinition(manifest: .init(id: "template", name: "Theme Template"),
        tokens: ThemeDefinition.macos.tokens))
}
