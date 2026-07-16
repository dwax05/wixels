// Quotes — port of cynaberii-quotes: a pixel speech bubble of a short niche
// tumblr-style meme line. The Übersicht widget rerolled on every wal recolour;
// here it picks a random line at launch and rerolls on click (interactive).
//
// Lines load from a JSON array of strings — set the file via this widget's
// [widget.options] path in desktop.toml (default ~/.config/wixels/quotes.json),
// overridable with WIXELS_QUOTES. Missing file → the hardcoded fallback line.
// idleStatic: no polling, redraws on palette change.

import SwiftUI
import WixelsKit

/// Loads the curated quote list once; hands out random picks. Immutable → Sendable.
struct QuoteSource: Sendable {
    let quotes: [String]

    static let maxWidth: CGFloat = 196   // bubble text wrap width
    static let fallback = ["the horrors persist but so do i"]

    /// `configPath` is the widget's `[widget.options] path`. Precedence: WIXELS_QUOTES
    /// env > that config path > the built-in default location.
    init(path configPath: String? = nil) {
        let path = Paths.resolve(env: "WIXELS_QUOTES", config: configPath,
                                 default: "~/.config/wixels/quotes.json")
        if let data = FileManager.default.contents(atPath: path),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String], !list.isEmpty {
            quotes = list
        } else {
            quotes = Self.fallback
        }
    }

    func random() -> String { quotes.randomElement() ?? Self.fallback[0] }

}

struct Quotes: ThemeableWixel {
    let source: QuoteSource

    static let kind = "quotes"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomLeft, offset: .init(width: 300, height: 90),
                                    size: .init(width: 250, height: 150)),
            build: { _, opts in Quotes(source: QuoteSource(path: opts.string("path"))) })
    }
    static let refresh: RefreshPolicy = .idleStatic
    static let interactive = true

    func sample() async -> String { source.random() }

    func render(_ s: String, _ theme: ThemeContext) -> some View {
        QuotesView(initial: s, source: source, theme: theme)
    }
}

private struct QuotesView: View {
    let initial: String
    let source: QuoteSource
    let theme: ThemeContext
    @State private var quote: String?

    private func line(_ s: String) -> some View {
        (Text("“ ").foregroundColor(theme.color(.accent)) + Text(s).foregroundColor(theme.color(.foreground)))
            .font(theme.font(.body))
            .lineSpacing(4)
            .frame(maxWidth: QuoteSource.maxWidth, alignment: .leading)
    }

    var body: some View {
        let text = quote ?? initial

        // Reserve the largest active-theme layout so rerolling cannot resize the
        // bubble. SwiftUI measures these with ThemeContext's font; no widget-owned
        // concrete typeface leaks into the package.
        return ZStack(alignment: .topLeading) {
            ForEach(source.quotes, id: \.self) { line($0).opacity(0) }
            line(text)
        }
            .themedCard(theme, insets: .init(top: 12, leading: 14, bottom: 12, trailing: 14))
            .contentShape(Rectangle())
            .onTapGesture { quote = source.random() }
    }
}
