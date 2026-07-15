import AppKit
import SwiftUI
import WixelsKit

@MainActor
private final class ContentSizeProbeState: ObservableObject {
    @Published var size: CGSize
    init(_ size: CGSize) { self.size = size }
}

private struct ContentSizeProbeView: View {
    @ObservedObject var state: ContentSizeProbeState
    let expandsToProposal: Bool
    var body: some View {
        let content = Color.clear.frame(width: state.size.width, height: state.size.height)
        if expandsToProposal { content.frame(maxWidth: .infinity, alignment: .leading) }
        else { content }
    }
}

private struct ContentSizeProbe: Wixel, @unchecked Sendable {
    static let kind = "content-size-probe"
    static let refresh: RefreshPolicy = .idleStatic
    let state: ContentSizeProbeState
    let expandsToProposal: Bool
    static func spec() -> WidgetSpec { fatalError("test-only direct mount") }
    func sample() async -> Int { 1 }
    @MainActor func render(_ sample: Int, _ palette: Palette) -> some View {
        ContentSizeProbeView(state: state, expandsToProposal: expandsToProposal)
    }
}

/// Integration coverage for the production layout seam. This loads the user's
/// real plugin set and options, mounts every widget at its plugin default, and
/// injects a no-op writer so the suite cannot modify desktop configuration.
@MainActor
func runLayoutTestSuite() -> Int32 {
    guard runContentSizingLayoutSuite() else { return 1 }
    let config = Config.load()
    let services = Services()
    let registrar = Registrar()
    _ = PluginLoader.load(into: registrar)
    let host = WidgetHost(palette: PaletteStore(colorsPath: config.colors.file,
                                                 overrides: config.colors.overrides),
                          placementWriter: { _ in })

    for entry in config.entries {
        if let spec = registrar.specs[entry.kind] {
            host.mount(spec.build(services, entry.options), placement: spec.defaultPlacement,
                       defaultPlacement: spec.defaultPlacement, configIndex: entry.sourceIndex)
        } else if let resolved = registrar.resolveThemed(kind: entry.kind,
            themeID: entry.theme ?? config.theme ?? "macos",
            services: services, options: entry.options) {
            host.mount(resolved.widget, placement: resolved.placement,
                       defaultPlacement: resolved.placement, configIndex: entry.sourceIndex)
        }
    }

    host.run()
    pumpWindowServer()
    let before = host.layoutSnapshot()
    host.resetLayout()
    pumpWindowServer()
    let after = host.layoutSnapshot()

    guard !before.isEmpty, before.count == after.count else {
        print("FAIL layout reset mounted \(before.count) production windows before and \(after.count) after")
        return 1
    }

    var failures = 0
    for expected in before {
        guard let actual = after.first(where: { $0.configIndex == expected.configIndex }) else {
            print("FAIL \(expected.kind)[\(expected.configIndex)] disappeared during reset")
            failures += 1
            continue
        }
        let stable = expected.sizing == .fixed
            ? actual.frame == expected.frame
            : preservesAnchor(expected.anchor, before: expected.frame, after: actual.frame)
        guard stable else {
            let dx = actual.frame.origin.x - expected.frame.origin.x
            let dy = actual.frame.origin.y - expected.frame.origin.y
            print("FAIL \(expected.kind)[\(expected.configIndex)] moved dx=\(dx) dy=\(dy) " +
                  "before=\(NSStringFromRect(expected.frame)) after=\(NSStringFromRect(actual.frame))")
            failures += 1
            continue
        }
        print("PASS \(expected.kind)[\(expected.configIndex)] \(expected.sizing == .fixed ? "frame unchanged" : "anchor preserved")")
    }

    print(failures == 0 ? "PASS production layout reset suite" :
          "FAIL production layout reset suite: \(failures) shifted window(s)")
    return failures == 0 ? 0 : 1
}

private func preservesAnchor(_ anchor: WixelsKit.Anchor, before: NSRect, after: NSRect) -> Bool {
    switch anchor {
    case .topLeft: return before.minX == after.minX && before.maxY == after.maxY
    case .topRight: return before.maxX == after.maxX && before.maxY == after.maxY
    case .bottomLeft: return before.minX == after.minX && before.minY == after.minY
    case .bottomRight: return before.maxX == after.maxX && before.minY == after.minY
    case .center: return before.midX == after.midX && before.midY == after.midY
    case .topCenter: return before.midX == after.midX && before.maxY == after.maxY
    }
}

/// Covers the host-only sizing seam independently of installed plugins. The first
/// frame must remain the declared fallback until sampling completes; afterwards
/// every anchor must retain its anchored edge as the content grows.
@MainActor
private func runContentSizingLayoutSuite() -> Bool {
    let initial = CGSize(width: 64, height: 40)
    let grown = CGSize(width: 140, height: 80)
    let anchors: [WixelsKit.Anchor] = [.topLeft, .topRight, .bottomLeft, .bottomRight, .center, .topCenter]
    let states = anchors.map { _ in ContentSizeProbeState(initial) }
    let host = WidgetHost(palette: PaletteStore(colorsPath: "/dev/null"), placementWriter: { _ in })
    for (index, anchor) in anchors.enumerated() {
        let placement = Placement(anchor: anchor, offset: .init(width: 13, height: -17),
                                  size: .init(width: 220, height: 160), sizing: .fitContent)
        host.mount(erase(ContentSizeProbe(state: states[index], expandsToProposal: false)), placement: placement,
                   defaultPlacement: placement, configIndex: index)
    }
    let fixed = Placement(anchor: .topLeft, size: .init(width: 91, height: 37))
    host.mount(erase(ContentSizeProbe(state: ContentSizeProbeState(initial), expandsToProposal: false)), placement: fixed,
               defaultPlacement: fixed, configIndex: anchors.count)
    let flexible = Placement(anchor: .topLeft, offset: .init(width: 300, height: -17),
                             size: .init(width: 220, height: 160), sizing: .fitContent)
    host.mount(erase(ContentSizeProbe(state: ContentSizeProbeState(initial), expandsToProposal: true)),
               placement: flexible, defaultPlacement: flexible, configIndex: anchors.count + 1)
    host.run()

    let fallback = host.layoutSnapshot().sorted { $0.configIndex < $1.configIndex }
    guard fallback.count == anchors.count + 2,
          fallback.prefix(anchors.count).allSatisfy({ $0.frame.size == .init(width: 220, height: 160) }),
          fallback[anchors.count + 1].frame.size == .init(width: 220, height: 160) else {
        print("FAIL fit-content fallback frame collapsed before first sample")
        host.shutdown()
        return false
    }

    pumpWindowServer()
    let measured = host.layoutSnapshot().sorted { $0.configIndex < $1.configIndex }
    guard measured.prefix(anchors.count).allSatisfy({ $0.frame.size == initial }),
          measured[anchors.count].frame.size == fixed.size,
          measured[anchors.count + 1].frame.size == initial else {
        print("FAIL fit-content measurement or fixed placement behavior: \(measured.map { NSStringFromRect($0.frame) })")
        host.shutdown()
        return false
    }

    for state in states { state.size = grown }
    pumpWindowServer()
    let resized = host.layoutSnapshot().sorted { $0.configIndex < $1.configIndex }
    var failures = 0
    for index in anchors.indices {
        let before = measured[index].frame, after = resized[index].frame
        let sameMinX = before.minX == after.minX
        let sameMaxX = before.maxX == after.maxX
        let sameMidX = before.midX == after.midX
        let sameMinY = before.minY == after.minY
        let sameMaxY = before.maxY == after.maxY
        let sameMidY = before.midY == after.midY
        let stable: Bool
        switch anchors[index] {
        case .topLeft: stable = sameMinX && sameMaxY
        case .topRight: stable = sameMaxX && sameMaxY
        case .bottomLeft: stable = sameMinX && sameMinY
        case .bottomRight: stable = sameMaxX && sameMinY
        case .center: stable = sameMidX && sameMidY
        case .topCenter: stable = sameMidX && sameMaxY
        }
        if after.size != grown || !stable {
            print("FAIL fit-content \(anchors[index]) did not preserve its anchored edge")
            failures += 1
        }
    }
    host.shutdown()
    print(failures == 0 ? "PASS fit-content layout suite" : "FAIL fit-content layout suite")
    return failures == 0
}

@MainActor
private func pumpWindowServer() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
}
