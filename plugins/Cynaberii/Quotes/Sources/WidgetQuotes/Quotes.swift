// Quotes — port of cynaberii-quotes: a pixel speech bubble of a short niche
// tumblr-style meme line. The Übersicht widget rerolled on every wal recolour;
// here it picks a random line at launch and rerolls on click (interactive).
//
// Lines load from a JSON array of strings — set the file via this widget's
// [widget.options] path in desktop.toml (default ~/.config/wixels/quotes.json),
// overridable with WIXELS_QUOTES. Missing file → the hardcoded fallback line.
// idleStatic: no polling, redraws on palette change.

import AppKit
import SwiftUI
import WixelsKit

/// Loads the curated quote list once; hands out random picks. Immutable → Sendable.
struct QuoteSource: Sendable {
    let quotes: [String]
    let tallest: String     // the line with the most wrapped height — sizes the bubble

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
        tallest = Self.tallestLine(quotes)
    }

    func random() -> String { quotes.randomElement() ?? Self.fallback[0] }

    /// Which quote wraps to the greatest height at the bubble width — measured once
    /// with TextKit. The absolute value needn't match SwiftUI's layout exactly; the
    /// ranking does, so the winner sizes the bubble correctly when SwiftUI draws it.
    private static func tallestLine(_ quotes: [String]) -> String {
        let font = NSFont(name: "Silkscreen", size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        let bound = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        var best = quotes.first ?? Self.fallback[0]
        var bestH: CGFloat = 0
        for q in quotes {
            let attr = NSAttributedString(string: "“ " + q, attributes: [.font: font])
            let h = attr.boundingRect(with: bound,
                                      options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            if h > bestH { bestH = h; best = q }
        }
        return best
    }
}

struct Quotes: ThemeableWixel {
    let source: QuoteSource

    static let kind = "quotes"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .bottomLeft, offset: .init(width: 300, height: 90),
                                    size: .init(width: 250, height: 150), sizing: .fitContent),
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

        // Reserve the height of the tallest quote so the bubble never resizes on
        // reroll: lay out only that one line invisibly (picked once at load) and
        // show the current line on top.
        return ZStack(alignment: .topLeading) {
            line(source.tallest).opacity(0)
            line(text)
        }
            .themedCard(theme, insets: .init(top: 12, leading: 14, bottom: 12, trailing: 14))
            .contentShape(Rectangle())
            .onTapGesture { quote = source.random() }
    }
}
