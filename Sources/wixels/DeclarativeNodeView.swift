import Foundation
import SwiftUI
import WixelsKit

struct DeclarativeNodeView: View {
    let node: DeclarativeNode
    let values: [String: String]
    let palette: Palette

    var body: some View { content }

    private var content: AnyView {
        switch node {
        case let .text(value, style, visible, action):
            return visible.isVisible(in: values)
                ? AnyView(decorated(
                    Text(value.resolve(in: values)).fixedSize(horizontal: false, vertical: true),
                    style: style, action: action))
                : AnyView(EmptyView())
        case let .image(value, style, visible, action):
            return visible.isVisible(in: values) ? AnyView(decorated(DeclarativeImage(source: value.resolve(in: values)), style: style, action: action)) : AnyView(EmptyView())
        case let .row(children, spacing, style, visible, action):
            return container(HStack(spacing: spacing) { ForEach(Array(children.enumerated()), id: \.offset) { _, child in DeclarativeNodeView(node: child, values: values, palette: palette) } }, style: style, visible: visible, action: action)
        case let .column(children, spacing, style, visible, action):
            return container(VStack(alignment: .leading, spacing: spacing) { ForEach(Array(children.enumerated()), id: \.offset) { _, child in DeclarativeNodeView(node: child, values: values, palette: palette) } }, style: style, visible: visible, action: action)
        case let .stack(children, style, visible, action):
            return container(ZStack { ForEach(Array(children.enumerated()), id: \.offset) { _, child in DeclarativeNodeView(node: child, values: values, palette: palette) } }, style: style, visible: visible, action: action)
        case let .spacer(length, visible):
            guard visible.isVisible(in: values) else { return AnyView(EmptyView()) }
            if let length { return AnyView(Spacer().frame(width: CGFloat(length), height: CGFloat(length))) }
            return AnyView(Spacer())
        }
    }

    /// Shared visibility gate for row/column/stack: container nodes only differ in
    /// which SwiftUI layout wraps their children.
    private func container<Content: View>(_ content: Content, style: WidgetStyle, visible: ValueBinding, action: DeclarativeAction?) -> AnyView {
        visible.isVisible(in: values) ? AnyView(decorated(content, style: style, action: action)) : AnyView(EmptyView())
    }

    private func decorated<Content: View>(_ content: Content, style: WidgetStyle, action: DeclarativeAction?) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
        return content
            .font(style.font)
            .foregroundStyle(style.foreground.color(in: palette))
            .lineSpacing(style.lineSpacing)
            .multilineTextAlignment(style.textAlignment.textAlignment)
            .frame(maxWidth: style.maxWidth, alignment: style.alignment.frameAlignment)
            .padding(style.padding)
            .clipShape(shape)
            // Fill drawn after the clip (themedCard pattern) so its shadow — the
            // offset silhouette — isn't clipped away with the content.
            .background {
                let fill = shape.fill(style.background.color(in: palette).opacity(style.backgroundOpacity))
                if let shadow = style.shadow {
                    fill.shadow(color: shadow.color.color(in: palette).opacity(shadow.opacity),
                                radius: shadow.blur, x: shadow.offsetX, y: shadow.offsetY)
                } else {
                    fill
                }
            }
            .overlay {
                // strokeBorder draws inside the bounds, so fit-content windows never clip it.
                if let border = style.border {
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .strokeBorder(border.color.color(in: palette), lineWidth: border.width)
                }
            }
            .overlay {
                if let inner = style.innerBorder {
                    RoundedRectangle(cornerRadius: max(0, style.radius - inner.inset), style: .continuous)
                        .strokeBorder(inner.color.color(in: palette), lineWidth: inner.width)
                        .padding(inner.inset)
                }
            }
            // Grow the layout by the shadow's overhang so fit-content windows
            // include it instead of clipping at the window edge.
            .padding(.trailing, max(0, style.shadow?.offsetX ?? 0))
            .padding(.bottom, max(0, style.shadow?.offsetY ?? 0))
            .padding(.leading, max(0, -(style.shadow?.offsetX ?? 0)))
            .padding(.top, max(0, -(style.shadow?.offsetY ?? 0)))
            .onTapGesture { if let action { DeclarativeCommand.run(action.command) } }
    }
}

private struct DeclarativeImage: View {
    let source: String
    var body: some View {
        if source.hasPrefix("https://"), let url = URL(string: source) {
            DeclarativeRemoteImage(url: url)
        } else if source.hasPrefix("/") || source.hasPrefix("file://") {
            if let image = NSImage(contentsOf: URL(string: source) ?? URL(fileURLWithPath: source)) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        } else { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
}

@MainActor
private final class DeclarativeImageCache: ObservableObject {
    static let shared = DeclarativeImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private init() { cache.countLimit = 32 }

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func fetch(_ url: URL) async -> NSImage? {
        if let cached = image(for: url) { return cached }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct DeclarativeRemoteImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else if finished { Image(systemName: "photo").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: url) {
            image = await DeclarativeImageCache.shared.fetch(url)
            finished = true
        }
    }
}

private enum DeclarativeCommand {
    static func run(_ command: String) {
        Task.detached(priority: .utility) { try? await CommandVariableStore.runAction(command) }
    }
}

func declarativeAccessibilityLabel(_ node: DeclarativeNode, values: [String: String]) -> String {
    switch node {
    case let .text(value, _, _, _): value.resolve(in: values)
    case .image: "image"
    case let .row(children, _, _, _, _), let .column(children, _, _, _, _), let .stack(children, _, _, _): children.map { declarativeAccessibilityLabel($0, values: values) }.joined(separator: " ")
    case .spacer: ""
    }
}
