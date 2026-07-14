import WixelsKit
import SwiftUI

@MainActor
enum SchedulerTests {
    static func run() async throws {
        try await startTicksActiveWidgetsAccordingToTheirRefreshPolicy()
        try await refreshOnceOnlyTicksActiveIdleStaticWidgets()
        try await overlappingPetReadsRemainValid()
        try universalThemeRegistryResolvesAndPreservesPlacement()
        print("PASS scheduler suite")
    }

    private static func universalThemeRegistryResolvesAndPreservesPlacement() throws {
        let registrar = Registrar()
        registrar.add(TestThemeable.spec())
        let native = ThemeDefinition(manifest: .init(id: "native", name: "Native"),
                                     tokens: ThemeDefinition.macos.tokens)
        registrar.add(native)
        let resolved = registrar.resolveThemed(kind: "test", themeID: "native",
                                               services: Services(), options: .empty)
        try check(resolved?.themeID == "native", "registered universal theme resolves")
        try check(resolved?.placement.size.width == 10, "theme cannot change widget placement")
        let fallback = registrar.resolveThemed(kind: "test", themeID: "missing",
                                               services: Services(), options: .empty)
        try check(fallback?.themeID == "macos", "unknown theme falls back to macos")
        registrar.add(ThemeDefinition(manifest: .init(id: "native", name: "Duplicate"),
                                      tokens: ThemeDefinition.cynaberii.tokens))
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
            music: MusicMonitor(cachePath: "/dev/null")
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

private struct TestThemeable: ThemeableWixel {
    static let kind = "test"
    static let refresh: RefreshPolicy = .idleStatic
    static func spec() -> ThemedWidgetSpec {
        ThemedWidgetSpec(widget: Self.self,
            defaultPlacement: .init(anchor: .center, size: .init(width: 10, height: 10)),
            build: { _, _ in Self() })
    }
    func sample() async -> Int { 1 }
    func render(_ sample: Int, _ theme: ThemeContext) -> some View { Text("\(sample)") }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct TestMain {
    static func main() async throws {
        try await SchedulerTests.run()
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
