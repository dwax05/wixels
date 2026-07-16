import SwiftUI
import WixelsKit
import TOMLKit

/// The single TOML representation of widget placement, shared by desktop.toml
/// parsing (`Config`) and group layout files (`LayoutStore`).
enum PlacementTOML {
    /// `logging` is true for user-authored desktop.toml, false for generated
    /// layout files where malformed values are silently skipped.
    static func placement(from row: TOMLTable, logging: Bool) -> PlacementOverride {
        var p = PlacementOverride()
        if let value = row["anchor"]?.string { p.anchor = WixelsKit.Anchor(rawValue: value) }
        if let pair = pair(row["offset"], name: "offset", logging: logging) { p.offset = pair }
        if let pair = pair(row["size"], name: "size", logging: logging) { p.size = pair }
        p.zBoost = row["zBoost"]?.int
        if let value = row["align"]?.string { p.align = alignment(value) }
        return p
    }

    private static func pair(_ value: TOMLValueConvertible?, name: String, logging: Bool) -> CGSize? {
        guard let array = value?.array, array.count >= 2 else { return nil }
        let values = Array(array)
        guard let x = number(values[0]), let y = number(values[1]) else {
            if logging { Log.note("invalid widget \(name) — ignoring") }
            return nil
        }
        return CGSize(width: x, height: y)
    }

    static func number(_ value: TOMLValueConvertible) -> CGFloat? {
        if let number = value.double, number.isFinite { return CGFloat(number) }
        if let integer = value.int { return CGFloat(integer) }
        return nil
    }

    static func numberString(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(Double(value))
    }

    /// The TOML `align` strings, mapped like `Anchor(rawValue:)` does for anchors —
    /// a lookup table rather than a hand-written switch (SwiftUI's `Alignment` isn't
    /// `RawRepresentable`, so this is the nearest equivalent).
    private static let alignments: [String: Alignment] = [
        "leading": .leading, "trailing": .trailing, "center": .center,
        "top": .top, "bottom": .bottom,
        "topLeading": .topLeading, "topTrailing": .topTrailing,
        "bottomLeading": .bottomLeading, "bottomTrailing": .bottomTrailing,
    ]

    static func alignment(_ value: String) -> Alignment? { alignments[value] }
    static func alignmentName(_ value: Alignment?) -> String? {
        alignments.first(where: { $0.value == value })?.key
    }
}
