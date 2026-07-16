@testable import WixelsKit
import SwiftUI
import Foundation

@MainActor
enum SchedulerTests {
    static func run() async throws {
        try coreAnimationYTranslationMatchesSwiftUI()
        try await startTicksActiveWidgetsAccordingToTheirRefreshPolicy()
        try await refreshOnceOnlyTicksActiveIdleStaticWidgets()
        try await overlappingPetReadsRemainValid()
        try universalThemeRegistryResolvesAndPreservesPlacement()
        try previewRegistryUsesFixturesAndKeepsLegacySpecsCompatible()
        try connectivityDoesNotTreatHiddenSSIDAsOffline()
        try paletteLayersResolvePerTheme()
        print("PASS scheduler suite")
    }

    /// SwiftUI's positive Y points down while a default CALayer's points up.
    /// This boundary test prevents decorative effects from being vertically
    /// mirrored when their SwiftUI offsets become CA transform tracks.
    private static func coreAnimationYTranslationMatchesSwiftUI() throws {
        try check(caTrackValue(-12, property: .offsetY).doubleValue == 12,
                  "negative SwiftUI Y rises in Core Animation")
        try check(caTrackValue(12, property: .offsetY).doubleValue == -12,
                  "positive SwiftUI Y falls in Core Animation")
    }

    private static func universalThemeRegistryResolvesAndPreservesPlacement() throws {
        let registrar = Registrar()
        registrar.add(TestThemeable.spec())
        let fallbackTheme = testTheme(id: "macos", rounded: true, color: RGB(10, 20, 30))
        let native = testTheme(id: "native", rounded: true, color: RGB(10, 20, 30))
        let pixel = testTheme(id: "pixel", rounded: false, color: RGB(40, 50, 60))
        registrar.add(fallbackTheme)
        try check(native.tokens.card.shape == .rounded(16), "macos theme rounds cards")
        try check(native.tokens.mediaShape == .rounded(8), "macos theme rounds media")
        try check(pixel.tokens.card.shape == .rectangle, "data-defined pixel theme keeps cards square")
        try check(pixel.tokens.mediaShape == .rectangle, "data-defined pixel theme keeps media square")
        registrar.add(native)
        let resolved = registrar.resolveThemed(kind: "test", themeID: "native",
                                               services: Services(), options: .empty)
        try check(resolved?.themeID == "native", "registered universal theme resolves")
        try check(resolved?.placement.size.width == 10, "theme cannot change widget placement")
        let fallback = registrar.resolveThemed(kind: "test", themeID: "missing",
                                               services: Services(), options: .empty)
        try check(fallback?.themeID == "macos", "unknown theme falls back to macos")
        registrar.add(pixel)
        registrar.add(testTheme(id: "native", rounded: false, color: RGB(40, 50, 60)))
        try check(registrar.resolveTheme("native") == native, "duplicate theme keeps first registration")
    }

    private static func startTicksActiveWidgetsAccordingToTheirRefreshPolicy() async throws {
        let interval = FakeTicker(kind: "interval", refresh: .interval(60))
        let idle = FakeTicker(kind: "idle", refresh: .idleStatic)
        let inactive = FakeTicker(kind: "inactive", refresh: .interval(60), active: false)
        let scheduler = Scheduler(loopInterval: .milliseconds(10))

        scheduler.add(interval)
        scheduler.add(idle)
        scheduler.add(inactive)
        scheduler.start()
        try await waitUntil { interval.tickCount == 1 && idle.tickCount == 1 }
        scheduler.stop()

        try check(interval.tickCount == 1, "interval widget ticks once at start")
        try check(idle.tickCount == 1, "idle-static widget ticks once at start")
        try check(inactive.tickCount == 0, "inactive interval widget does not tick")
    }

    private static func refreshOnceOnlyTicksActiveIdleStaticWidgets() async throws {
        let active = FakeTicker(kind: "active", refresh: .idleStatic)
        let inactive = FakeTicker(kind: "inactive", refresh: .idleStatic, active: false)
        let scheduler = Scheduler(loopInterval: .milliseconds(10))
        scheduler.add(active)
        scheduler.add(inactive)

        scheduler.refreshOnce()
        try await waitUntil { active.tickCount == 1 }

        try check(active.tickCount == 1, "refresh ticks active idle-static widget")
        try check(inactive.tickCount == 0, "refresh skips inactive idle-static widget")
    }

    private static func overlappingPetReadsRemainValid() async throws {
        let source = PetSource(
            cpu: CPUSource(minInterval: 0),
            music: MusicMonitor()
        )
        let readings = await withTaskGroup(of: PetState.self, returning: [PetState].self) { group in
            for _ in 0..<8 { group.addTask { await source.read() } }
            var values: [PetState] = []
            for await value in group { values.append(value) }
            return values
        }

        try check(readings.count == 8, "overlapping pet reads all complete")
        try check(readings.allSatisfy { (0...1).contains($0.cpu) },
                  "overlapping pet reads return valid CPU samples")
    }

    private static func paletteLayersResolvePerTheme() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let configured = "/tmp/wixels-configured-colors-\(pid).json"
        let selected = "/tmp/wixels-selected-colors-\(pid).json"
        defer {
            unsetenv("WIXELS_COLORS")
            try? FileManager.default.removeItem(atPath: configured)
            try? FileManager.default.removeItem(atPath: selected)
        }
        try """
        {"special":{"background":"111111"},"colors":{"color0":"222222","color1":"333333"}}
        """.write(toFile: configured, atomically: true, encoding: .utf8)
        try """
        {"special":{"foreground":"444444"},"colors":{"color0":"555555"}}
        """.write(toFile: selected, atomically: true, encoding: .utf8)
        setenv("WIXELS_COLORS", selected, 1)
        let store = PaletteStore(colorsPath: configured,
            overrides: .init(background: RGB(hex: "666666"), accents: [RGB(hex: "777777")]))
        defer { store.stop() }

        let macosTheme = testTheme(id: "macos", rounded: true, color: RGB(10, 20, 30))
        let pixelTheme = testTheme(id: "pixel", rounded: false, color: RGB(40, 50, 60))
        let macos = store.resolvedPalette(for: macosTheme)
        let cynaberii = store.resolvedPalette(for: pixelTheme)
        try check(macos.background == RGB(hex: "666666") && macos.foreground == RGB(hex: "444444") &&
                  macos.c(0) == RGB(hex: "777777"),
                  "TOML palette values override environment-selected file values")
        try check(macos.c(1) == macosTheme.defaultPalette.c(1),
                  "environment-selected file replaces configured file rather than composing with it")
        try check(macos.c(2) == macosTheme.defaultPalette.c(2) &&
                  cynaberii.c(2) == pixelTheme.defaultPalette.c(2) &&
                  macos.c(2) != cynaberii.c(2),
                  "partial palettes fall back per value to each widget theme")
    }

    private static func previewRegistryUsesFixturesAndKeepsLegacySpecsCompatible() throws {
        let registrar = Registrar()
        registrar.add(testTheme(id: "macos", rounded: true, color: RGB(10, 20, 30)))
        registrar.add(TestThemeable.spec())
        registrar.add(LegacyThemeable.spec())
        let previews = registrar.registeredPreviews(services: Services(), themeID: "macos")
        try check(previews.count == 1 && previews.first?.kind == "test" && previews.first?.name == "Fixture",
                  "preview registration enumerates deterministic themed fixtures")
        try check(!previews.contains { $0.kind == "legacy" },
                  "legacy themed specs remain source-compatible with no previews")
    }

    private static func connectivityDoesNotTreatHiddenSSIDAsOffline() throws {
        try check(ConnectivitySource.interpret(reachable: true, ssid: nil, hasWiFiInterface: true)
                    == .init(connected: true, label: "Online"),
                  "reachable Wi-Fi without an SSID uses a compact online state")
        try check(ConnectivitySource.interpret(reachable: true, ssid: nil, hasWiFiInterface: false)
                    == .init(connected: true, label: "Online"),
                  "reachable non-Wi-Fi network is online")
        try check(ConnectivitySource.interpret(reachable: false, ssid: "Studio", hasWiFiInterface: true)
                    == .init(connected: false, label: "Offline"),
                  "unreachable network remains offline")
    }

    private static func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await clock.sleep(for: .milliseconds(5))
        }
        throw TestFailure("timed out waiting for scheduler")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
        print("PASS \(message)")
    }
}

private func testTheme(id: String, rounded: Bool, color: RGB) -> ThemeDefinition {
    let source: ThemeColor = .rgb(color)
    return ThemeDefinition(manifest: .init(id: id, name: id), tokens: .init(
        colors: .init(background: source, foreground: source, secondary: source, accent: source,
            alternateAccent: source, positive: source, warning: source, negative: source,
            muted: source, border: source, shadow: source),
        typography: .init(title: .init(size: 12), body: .init(size: 11), label: .init(size: 10),
            caption: .init(size: 9), symbol: .init(size: 12)),
        card: .init(fill: .color(source), shape: rounded ? .rounded(16) : .rectangle),
        mediaShape: rounded ? .rounded(8) : .rectangle),
        defaultPalette: .init(background: color, foreground: color, accents: Array(repeating: color, count: 16)))
}

private struct TestThemeable: ThemeableWixel {
    static let kind = "test"
    static let refresh: RefreshPolicy = .idleStatic
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .center, size: .init(width: 10, height: 10)),
            previews: [.init("Fixture", sample: 42)],
            build: { _, _ in Self() })
    }
    func sample() async -> Int { 1 }
    func render(_ sample: Int, _ theme: ThemeContext) -> some View { Text("\(sample)") }
}

private struct LegacyThemeable: ThemeableWixel {
    static let kind = "legacy"
    static let refresh: RefreshPolicy = .idleStatic
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .center, size: .init(width: 10, height: 10)),
            build: { _, _ in Self() })
    }
    func sample() async -> Int { 0 }
    func render(_ sample: Int, _ theme: ThemeContext) -> some View { Text("\(sample)") }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct TestMain {
    static func main() async throws {
        // Re-executed as the throwaway "host" of the force-quit lifeline test.
        if await StreamLifelineTests.runHostModeIfRequested() { return }
        try await SchedulerTests.run()
        try await StreamLifelineTests.run()
    }
}

@MainActor
private final class FakeTicker: WidgetTicker {
    let kind: String
    let refresh: RefreshPolicy
    let interactive = false
    var active: Bool
    private(set) var tickCount = 0

    init(kind: String, refresh: RefreshPolicy, active: Bool = true) {
        self.kind = kind
        self.refresh = refresh
        self.active = active
    }

    func tick() async { tickCount += 1 }
}
