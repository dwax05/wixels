import Foundation
import SwiftUI
import WixelsKit
import TOMLKit

/// One TOML document per plugin group. Filename encoding is deliberately boring
/// and reversible (UTF-8 hex), leaving group names unrestricted and safe.
enum LayoutStore {
    static var directory: String { (Config.path as NSString).deletingLastPathComponent + "/layouts" }
    static func filename(for group: String) -> String {
        group.utf8.map { String(format: "%02x", $0) }.joined() + ".toml"
    }
    static func path(for group: String) -> String { directory + "/" + filename(for: group) }
    static func exists(group: String) -> Bool { FileManager.default.fileExists(atPath: path(for: group)) }

    static func load(group: String) -> [String: PlacementOverride] {
        guard let text = try? String(contentsOfFile: path(for: group), encoding: .utf8),
              let table = try? TOMLTable(string: text),
              table["group"]?.string == group else { return [:] }
        var result: [String: PlacementOverride] = [:]
        for item in table["widget"]?.array ?? TOMLArray() {
            guard let row = item.table, let id = row["id"]?.string, !id.isEmpty else { continue }
            result[id] = placement(from: row)
        }
        return result
    }

    static func write(group: String, records: [LayoutRecord]) {
        do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) }
        catch { Log.note("failed to create layouts directory: \(error)"); return }
        // A save contains only mounted widgets. Keep records for configured rows
        // that are currently disabled or whose plugin is unavailable; the current
        // mounted state wins if it has the same stable ID.
        var placements = load(group: group)
        for record in records {
            placements[record.id] = PlacementOverride(anchor: record.placement.anchor,
                                                       offset: record.placement.offset,
                                                       size: record.placement.size,
                                                       zBoost: record.placement.zBoost,
                                                       align: record.placement.align)
        }
        var out = "# Wixels layout for \(group)\n# This file is generated; desktop.toml keeps enablement and options.\n\ngroup = \"\(escape(group))\"\n"
        for id in placements.keys.sorted() {
            guard let placement = placements[id] else { continue }
            out += "\n[[widget]]\nid = \"\(escape(id))\"\n"
            if let anchor = placement.anchor { out += "anchor = \"\(anchor.rawValue)\"\n" }
            if let offset = placement.offset { out += "offset = [\(number(offset.width)), \(number(offset.height))]\n" }
            if let size = placement.size { out += "size = [\(number(size.width)), \(number(size.height))]\n" }
            if let zBoost = placement.zBoost { out += "zBoost = \(zBoost)\n" }
            if let align = PlacementTOML.alignmentName(placement.align) { out += "align = \"\(align)\"\n" }
        }
        if (try? out.write(toFile: path(for: group), atomically: true, encoding: .utf8)) == nil { Log.note("failed to write layout for \(group)") }
    }

    private static func placement(from row: TOMLTable) -> PlacementOverride {
        PlacementTOML.placement(from: row, logging: false)
    }
    private static func number(_ value: CGFloat) -> String { PlacementTOML.numberString(value) }
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}
