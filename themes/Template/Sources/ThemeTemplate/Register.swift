import WixelsKit

// Copy this package and define one universal aesthetic token set. Themes never
// import widget sample types and cannot replace widget content or placement.
@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>.fromOpaque(context).takeUnretainedValue()
    let accent: ThemeColor = .rgb(RGB(64, 120, 200))
    registrar.add(ThemeDefinition(manifest: .init(id: "template", name: "Theme Template"), tokens: .init(
        colors: .init(background: .system(.background), foreground: .system(.foreground), secondary: .system(.secondary),
            accent: accent, alternateAccent: accent, positive: .system(.positive), warning: .system(.warning),
            negative: .system(.negative), muted: .system(.muted), border: .system(.border), shadow: .system(.shadow)),
        typography: .init(title: .init(weight: .bold, size: 18), body: .init(size: 13), label: .init(size: 11),
            caption: .init(size: 9), symbol: .init(size: 16)),
        card: .init(fill: .regularMaterial, shape: .rounded(12), borderWidth: 1), mediaShape: .rounded(6)),
        defaultPalette: .fallback))
}
