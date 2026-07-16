import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    Unmanaged<Registrar>.fromOpaque(context).takeUnretainedValue().add(cynaberiiTheme)
}

private let cynaberiiTheme = ThemeDefinition(
    manifest: .init(id: "cynaberii", name: "Cynaberii"),
    tokens: .init(
        colors: .init(background: .pywalBackground, foreground: .pywalForeground, secondary: .pywal(6), accent: .pywal(4),
            alternateAccent: .pywal(3), positive: .pywal(2), warning: .pywal(3), negative: .pywal(1), muted: .pywal(8),
            border: .pywal(4), shadow: .pywal(3)),
        typography: .init(title: .init(.custom("Silkscreen"), weight: .bold, size: 12),
            body: .init(.custom("Silkscreen"), size: 11), label: .init(.custom("Silkscreen"), size: 9),
            caption: .init(.custom("Silkscreen"), size: 8), symbol: .init(.custom("Silkscreen"), size: 16)),
        card: .init(fill: .color(.pywalBackground), shape: .rectangle, borderWidth: 4, shadowX: 4, shadowY: 4),
        mediaShape: .rectangle),
    defaultPalette: .init(background: RGB(22, 16, 39), foreground: RGB(196, 195, 201), accents: [
        RGB(22, 16, 39), RGB(137, 108, 156), RGB(135, 118, 171), RGB(126, 129, 174),
        RGB(151, 145, 174), RGB(167, 149, 211), RGB(192, 191, 197), RGB(196, 195, 201),
        RGB(101, 95, 117), RGB(137, 108, 156), RGB(135, 118, 171), RGB(126, 129, 174),
        RGB(151, 145, 174), RGB(167, 149, 211), RGB(192, 191, 197), RGB(196, 195, 201)
    ]))
