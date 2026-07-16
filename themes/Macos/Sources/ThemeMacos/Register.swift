import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    Unmanaged<Registrar>.fromOpaque(context).takeUnretainedValue().add(macosTheme)
}

private let macosTheme = ThemeDefinition(
    manifest: .init(id: "macos", name: "macOS"),
    tokens: .init(
        colors: .init(background: .system(.background), foreground: .system(.foreground), secondary: .system(.secondary),
            accent: .system(.accent), alternateAccent: .system(.alternateAccent), positive: .system(.positive),
            warning: .system(.warning), negative: .system(.negative), muted: .system(.muted), border: .system(.border), shadow: .system(.shadow)),
        typography: .init(title: .init(design: .rounded, weight: .semibold, size: 18),
            body: .init(size: 13), label: .init(weight: .medium, size: 11), caption: .init(size: 9),
            symbol: .init(weight: .semibold, size: 16)),
        card: .init(fill: .regularMaterial, shape: .rounded(16), borderWidth: 0.5, shadowBlur: 8, shadowY: 3, opacity: 0.96),
        mediaShape: .rounded(8)),
    defaultPalette: .init(background: RGB(242, 242, 247), foreground: RGB(28, 28, 30), accents: [
        RGB(28, 28, 30), RGB(255, 59, 48), RGB(52, 199, 89), RGB(255, 149, 0),
        RGB(0, 122, 255), RGB(175, 82, 222), RGB(90, 200, 250), RGB(142, 142, 147),
        RGB(99, 99, 102), RGB(72, 72, 74), RGB(142, 142, 147), RGB(174, 174, 178),
        RGB(199, 199, 204), RGB(209, 209, 214), RGB(229, 229, 234), RGB(242, 242, 247)
    ]))
