import AppKit
import SwiftUI

/// The versioned, neutral rendering interface shared by the host and extensions.
/// Concrete themes declare the range they support in their package manifest.
public enum WixelsKitAPI {
    public static let version = "0.2.0"
}

public struct ThemeManifest: Sendable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}

public enum ThemeSemanticColor: String, Sendable, CaseIterable {
    case background, foreground, secondary, accent, alternateAccent
    case positive, warning, negative, muted, border, shadow
}

public enum ThemeColor: Sendable, Equatable {
    case system(ThemeSemanticColor)
    case rgb(RGB)
    case pywal(Int)
    case pywalBackground
    case pywalForeground
}

public struct ThemeColors: Sendable, Equatable {
    public var background, foreground, secondary, accent, alternateAccent: ThemeColor
    public var positive, warning, negative, muted, border, shadow: ThemeColor
    public init(background: ThemeColor, foreground: ThemeColor, secondary: ThemeColor,
                accent: ThemeColor, alternateAccent: ThemeColor, positive: ThemeColor,
                warning: ThemeColor, negative: ThemeColor, muted: ThemeColor,
                border: ThemeColor, shadow: ThemeColor) {
        self.background = background; self.foreground = foreground; self.secondary = secondary
        self.accent = accent; self.alternateAccent = alternateAccent; self.positive = positive
        self.warning = warning; self.negative = negative; self.muted = muted
        self.border = border; self.shadow = shadow
    }
    public subscript(_ role: ThemeSemanticColor) -> ThemeColor {
        switch role {
        case .background: background; case .foreground: foreground; case .secondary: secondary
        case .accent: accent; case .alternateAccent: alternateAccent; case .positive: positive
        case .warning: warning; case .negative: negative; case .muted: muted
        case .border: border; case .shadow: shadow
        }
    }
}

public enum ThemeFontFamily: Sendable, Equatable { case system, custom(String) }
public enum ThemeFontDesign: Sendable, Equatable { case `default`, rounded, serif, monospaced }
public enum ThemeFontWeight: Sendable, Equatable { case regular, medium, semibold, bold }
public enum ThemeTextRole: Sendable, CaseIterable { case title, body, label, caption, symbol }
public struct ThemeFont: Sendable, Equatable {
    public var family: ThemeFontFamily; public var design: ThemeFontDesign
    public var weight: ThemeFontWeight; public var size: CGFloat
    public init(_ family: ThemeFontFamily = .system, design: ThemeFontDesign = .default,
                weight: ThemeFontWeight = .regular, size: CGFloat) {
        self.family = family; self.design = design; self.weight = weight; self.size = size
    }
}
public struct ThemeTypography: Sendable, Equatable {
    public var title, body, label, caption, symbol: ThemeFont
    public init(title: ThemeFont, body: ThemeFont, label: ThemeFont, caption: ThemeFont, symbol: ThemeFont) {
        self.title = title; self.body = body; self.label = label; self.caption = caption; self.symbol = symbol
    }
    public subscript(_ role: ThemeTextRole) -> ThemeFont {
        switch role { case .title: title; case .body: body; case .label: label; case .caption: caption; case .symbol: symbol }
    }
}

public enum ThemeCardFill: Sendable, Equatable { case color(ThemeColor), regularMaterial }
public enum ThemeShape: Shape, Sendable, Equatable {
    case rectangle, rounded(CGFloat)

    public func path(in rect: CGRect) -> Path {
        switch self {
        case .rectangle: Rectangle().path(in: rect)
        case .rounded(let radius): RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }
}
public struct ThemeCard: Sendable, Equatable {
    public var fill: ThemeCardFill; public var shape: ThemeShape
    public var borderWidth, shadowBlur, shadowX, shadowY, opacity: CGFloat
    public init(fill: ThemeCardFill, shape: ThemeShape, borderWidth: CGFloat = 0,
                shadowBlur: CGFloat = 0, shadowX: CGFloat = 0, shadowY: CGFloat = 0, opacity: CGFloat = 1) {
        self.fill = fill; self.shape = shape; self.borderWidth = borderWidth
        self.shadowBlur = shadowBlur; self.shadowX = shadowX; self.shadowY = shadowY; self.opacity = opacity
    }
}
public struct ThemeMetrics: Sendable, Equatable {
    public var spacingScale: CGFloat; public var paddingScale: CGFloat
    public init(spacingScale: CGFloat = 1, paddingScale: CGFloat = 1) {
        self.spacingScale = spacingScale; self.paddingScale = paddingScale
    }
}
public struct ThemeTokens: Sendable, Equatable {
    public var colors: ThemeColors; public var typography: ThemeTypography
    public var card: ThemeCard; public var mediaShape: ThemeShape; public var metrics: ThemeMetrics
    public init(colors: ThemeColors, typography: ThemeTypography, card: ThemeCard,
                mediaShape: ThemeShape, metrics: ThemeMetrics = .init()) {
        self.colors = colors; self.typography = typography; self.card = card
        self.mediaShape = mediaShape; self.metrics = metrics
    }
}
public struct ThemeDefinition: Sendable, Equatable {
    public let manifest: ThemeManifest; public let tokens: ThemeTokens; public let defaultPalette: Palette
    public init(manifest: ThemeManifest, tokens: ThemeTokens, defaultPalette: Palette) {
        self.manifest = manifest; self.tokens = tokens; self.defaultPalette = defaultPalette
    }
}

public struct ThemeContext: Sendable {
    public let definition: ThemeDefinition; public let palette: Palette
    public init(definition: ThemeDefinition, palette: Palette) { self.definition = definition; self.palette = palette }
    public var tokens: ThemeTokens { definition.tokens }
    public func color(_ role: ThemeSemanticColor) -> Color { resolve(tokens.colors[role]) }
    public func resolve(_ source: ThemeColor) -> Color {
        switch source {
        case .rgb(let value): value.color
        case .pywal(let index): palette.c(index).color
        case .pywalBackground: palette.background.color
        case .pywalForeground: palette.foreground.color
        case .system(let role): Self.systemColor(role)
        }
    }
    public func font(_ role: ThemeTextRole) -> Font {
        let token = tokens.typography[role]
        let weight: Font.Weight = switch token.weight { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold }
        switch token.family {
        case .custom(let name): return .custom(name, fixedSize: token.size).weight(weight)
        case .system:
            let design: Font.Design = switch token.design { case .default: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
            return .system(size: token.size, weight: weight, design: design)
        }
    }
    private static func systemColor(_ role: ThemeSemanticColor) -> Color {
        switch role {
        case .background: Color(nsColor: .windowBackgroundColor)
        case .foreground: Color(nsColor: .labelColor)
        case .secondary: Color(nsColor: .secondaryLabelColor)
        case .accent: .accentColor
        case .alternateAccent: .purple
        case .positive: .green
        case .warning: .orange
        case .negative: .red
        case .muted: Color(nsColor: .tertiaryLabelColor)
        case .border: Color(nsColor: .separatorColor)
        case .shadow: .black
        }
    }
}

private struct ThemeCardModifier: ViewModifier {
    let theme: ThemeContext; let insets: EdgeInsets; let customFill: Color?
    @ViewBuilder func body(content: Content) -> some View {
        let card = theme.tokens.card
        let shape = card.shape
        content.padding(insets)
            .clipShape(shape)
            .background {
                Group {
                    if let customFill { shape.fill(customFill) }
                    else if case .regularMaterial = card.fill { shape.fill(.regularMaterial) }
                    else if case .color(let c) = card.fill { shape.fill(theme.resolve(c).opacity(card.opacity)) }
                }
                .shadow(color: theme.color(.shadow).opacity(0.3), radius: card.shadowBlur,
                        x: card.shadowX, y: card.shadowY)
            }
            .overlay(shape.stroke(theme.color(.border), lineWidth: card.borderWidth))
            .padding(.trailing, max(0, card.shadowX)).padding(.bottom, max(0, card.shadowY))
    }
}
public extension View {
    func themedCard(_ theme: ThemeContext, fill: Color? = nil,
                    insets: EdgeInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)) -> some View {
        modifier(ThemeCardModifier(theme: theme, insets: .init(top: insets.top * theme.tokens.metrics.paddingScale,
            leading: insets.leading * theme.tokens.metrics.paddingScale, bottom: insets.bottom * theme.tokens.metrics.paddingScale,
            trailing: insets.trailing * theme.tokens.metrics.paddingScale), customFill: fill))
    }

    func themedMedia(_ theme: ThemeContext, border: Color, lineWidth: CGFloat) -> some View {
        let shape = theme.tokens.mediaShape
        return clipShape(shape).overlay(
            shape.stroke(border, lineWidth: lineWidth * 2).clipShape(shape)
        )
    }
}
