import SwiftUI

/// Small, semantic building blocks for desktop-native widgets. They deliberately
/// remain ordinary SwiftUI views: authors can mix them with custom composition.
public struct NativeCard<Content: View>: View {
    let theme: ThemeContext
    @ViewBuilder let content: () -> Content
    public init(theme: ThemeContext, @ViewBuilder content: @escaping () -> Content) {
        self.theme = theme; self.content = content
    }
    public var body: some View { content().themedCard(theme) }
}

public struct NativeHeader: View {
    let title: String; let symbol: String; let theme: ThemeContext
    public init(_ title: String, symbol: String, theme: ThemeContext) {
        self.title = title; self.symbol = symbol; self.theme = theme
    }
    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(theme.font(.symbol)).foregroundStyle(theme.color(.accent))
                .accessibilityHidden(true)
            Text(title).font(theme.font(.label)).foregroundStyle(theme.color(.secondary))
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine).accessibilityLabel(title)
    }
}

public struct NativeMetric: View {
    let value: String; let label: String; let theme: ThemeContext
    public init(_ value: String, label: String, theme: ThemeContext) {
        self.value = value; self.label = label; self.theme = theme
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(theme.font(.title)).foregroundStyle(theme.color(.foreground))
            Text(label).font(theme.font(.label)).foregroundStyle(theme.color(.secondary))
        }.accessibilityElement(children: .combine).accessibilityLabel("\(label): \(value)")
    }
}

public struct NativeStatusRow: View {
    let symbol: String; let title: String; let value: String; let theme: ThemeContext
    public init(symbol: String, title: String, value: String, theme: ThemeContext) {
        self.symbol = symbol; self.title = title; self.value = value; self.theme = theme
    }
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(theme.color(.accent))
            Text(title).foregroundStyle(theme.color(.secondary))
            Spacer(minLength: 8)
            Text(value).foregroundStyle(theme.color(.foreground)).monospacedDigit()
        }.font(theme.font(.body)).accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(value)")
    }
}

public struct NativeStateView: View {
    public enum Kind { case empty, error, permission }
    let kind: Kind; let message: String; let theme: ThemeContext
    public init(_ kind: Kind, message: String, theme: ThemeContext) {
        self.kind = kind; self.message = message; self.theme = theme
    }
    public var body: some View {
        let details: (String, ThemeSemanticColor) = switch kind {
        case .empty: ("tray", .muted); case .error: ("exclamationmark.triangle", .negative)
        case .permission: ("lock", .warning)
        }
        HStack(spacing: 8) {
            Image(systemName: details.0).foregroundStyle(theme.color(details.1))
            Text(message).font(theme.font(.body)).foregroundStyle(theme.color(.secondary))
        }.accessibilityElement(children: .combine).accessibilityLabel(message)
    }
}
