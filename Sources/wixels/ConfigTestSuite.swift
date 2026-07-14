import Foundation
import WixelsKit

func runConfigTestSuite() -> Int32 {
    do {
        let legacy = try Config.parse("[[widget]]\nkind = \"clock\"")
        try expect(legacy.theme == nil && legacy.entries[0].theme == nil,
                   "missing theme selects macos at resolution")

        let selected = try Config.parse("""
        [theme]
        default = "macos"
        [[widget]]
        kind = "clock"
        [[widget]]
        kind = "stats"
        theme = "cynaberii"
        """)
        try expect(selected.theme == "macos", "global theme parses")
        try expect(selected.entries[1].theme == "cynaberii", "widget theme override parses")

        let malformed = try Config.parse("""
        [theme]
        default = "Not Valid"
        [[widget]]
        kind = "clock"
        theme = "also_bad"
        """)
        try expect(malformed.theme == nil && malformed.entries[0].theme == nil,
                   "malformed theme IDs are ignored")

        let explicit = try Config.parse("""
        [[widget]]
        kind = "clock"
        anchor = "bottomLeft"
        offset = [4, 5]
        """).entries[0]
        let base = WixelsKit.Placement(anchor: .topCenter, offset: .zero,
                                       size: .init(width: 10, height: 20))
        let placed = explicit.placement.apply(to: base)
        try expect(placed.anchor == .bottomLeft && placed.offset.width == 4 && placed.size == base.size,
                   "explicit placement fields override widget defaults selectively")
        print("PASS config suite")
        return 0
    } catch {
        print("FAIL config suite: \(error)")
        return 1
    }
}

private struct ConfigTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ConfigTestFailure(description: message) }
    print("PASS \(message)")
}
