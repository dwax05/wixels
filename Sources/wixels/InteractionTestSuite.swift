import AppKit
import SwiftUI
import WixelsKit

@MainActor
private final class InteractionProbeState: ObservableObject {
    @Published private(set) var clicks = 0
    func click() { clicks += 1 }
}

private struct InteractionProbe: Wixel, @unchecked Sendable {
    static let kind = "interaction-probe"
    static let refresh: RefreshPolicy = .idleStatic
    static let interactive = true

    let state: InteractionProbeState

    static func spec() -> WidgetSpec {
        fatalError("interaction probes are mounted directly by the internal test suite")
    }

    func sample() async -> Int { 0 }

    @MainActor
    func render(_ sample: Int, _ palette: Palette) -> some View {
        Color(red: 0.15, green: 0.35, blue: 0.75)
            .contentShape(Rectangle())
            .onTapGesture { state.click() }
    }
}

private struct InteractionTestSession {
    let host: WidgetHost
    let probes: [InteractionProbeState]
}

/// WindowServer-level coverage for interactive windows. It deliberately uses CGEvent
/// instead of calling AppKit or SwiftUI handlers, and never reads or writes user config.
@MainActor
func runInteractionTestSuite() -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    guard CGPreflightPostEventAccess() else {
        print("FAIL interaction tests require Accessibility permission to post CGEvents")
        return 2
    }

    let repetitions = interactionTestRepetitions()
    var session = makeInteractionTestSession()
    pumpInteractionEvents()

    guard verifyClick(&session, phase: "launch") else { return 1 }

    for iteration in 1...repetitions {
        switchForegroundApplication()
        pumpInteractionEvents(0.08)
        guard verifyClick(&session, phase: "app-switch #\(iteration)") else { return 1 }
    }
    if ProcessInfo.processInfo.environment["WIXELS_INTERACTION_SCENARIO"] == "app-switch" {
        session.host.shutdown()
        print("PASS interaction app-switch suite (\(repetitions) repetition(s))")
        return 0
    }

    for iteration in 1...repetitions {
        session.host.setEditMode(true)
        pumpInteractionEvents(0.05)
        session.host.endEditMode(save: false)
        pumpInteractionEvents(0.05)
        guard verifyClick(&session, phase: "edit-cancel #\(iteration)") else { return 1 }
    }

    for iteration in 1...repetitions {
        session.host.setEditMode(true)
        pumpInteractionEvents(0.05)
        guard dragFirstWindow(session.host, by: .init(width: 1, height: 0)) else {
            print("FAIL edit-save #\(iteration): could not post drag")
            return 1
        }
        session.host.endEditMode(save: true)
        pumpInteractionEvents(0.05)
        guard verifyClick(&session, phase: "edit-save #\(iteration)") else { return 1 }
    }

    for iteration in 1...repetitions {
        session.host.shutdown()
        session = makeInteractionTestSession()
        pumpInteractionEvents(0.1)
        guard verifyClick(&session, phase: "rebuild #\(iteration)") else { return 1 }
    }

    for iteration in 1...repetitions {
        session.host.setEditMode(true)
        pumpInteractionEvents(0.05)
        _ = dragFirstWindow(session.host, by: .init(width: 1, height: 0))
        session.host.endEditMode(save: true)
        session.host.shutdown()
        session = makeInteractionTestSession()
        pumpInteractionEvents(0.1)
        guard verifyClick(&session, phase: "edit-save+rebuild #\(iteration)") else { return 1 }
    }

    session.host.shutdown()
    print("PASS interaction suite (\(repetitions) repetition(s) per transition)")
    return 0
}

@MainActor
private func switchForegroundApplication() {
    let previous = NSWorkspace.shared.frontmostApplication
    let finder = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.finder"
    ).first
    _ = finder?.activate(options: [])
    pumpInteractionEvents(0.05)
    if previous?.processIdentifier != finder?.processIdentifier {
        _ = previous?.activate(options: [])
    }
}

@MainActor
private func makeInteractionTestSession() -> InteractionTestSession {
    let probes = [InteractionProbeState(), InteractionProbeState()]
    let host = WidgetHost(palette: PaletteStore(colorsPath: "/dev/null"), placementWriter: { _ in })
    let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    let probeZBoost = NSWindow.Level.floating.rawValue - desktopIconLevel
    let placements = [
        Placement(anchor: .topLeft, offset: .init(width: 40, height: -120),
                  size: .init(width: 96, height: 64), zBoost: probeZBoost),
        Placement(anchor: .topLeft, offset: .init(width: 160, height: -120),
                  size: .init(width: 96, height: 64), zBoost: probeZBoost),
    ]
    for index in probes.indices {
        host.mount(erase(InteractionProbe(state: probes[index])), placement: placements[index],
                   defaultPlacement: placements[index], configIndex: index)
    }
    host.run()
    return InteractionTestSession(host: host, probes: probes)
}

@MainActor
private func verifyClick(_ session: inout InteractionTestSession, phase: String) -> Bool {
    let frames = session.host.layoutSnapshot().sorted { $0.configIndex < $1.configIndex }
    guard frames.count == session.probes.count else {
        print("FAIL \(phase): mounted \(frames.count) windows, expected \(session.probes.count)")
        return false
    }
    let before = session.probes.map(\.clicks)
    for frame in frames { postClick(at: frame.frame.center) }
    pumpInteractionEvents(0.12)
    let after = session.probes.map(\.clicks)
    guard zip(before, after).allSatisfy({ $1 == $0 + 1 }) else {
        print("FAIL \(phase): both probe widgets must react; before=\(before) after=\(after)")
        for state in session.host.interactionSnapshot() { print("  \(state)") }
        return false
    }
    print("PASS \(phase): \(after)")
    return true
}

@MainActor
private func dragFirstWindow(_ host: WidgetHost, by delta: CGSize) -> Bool {
    guard let frame = host.layoutSnapshot().min(by: { $0.configIndex < $1.configIndex })?.frame else {
        return false
    }
    let start = cgPoint(fromAppKit: frame.center)
    let end = CGPoint(x: start.x + delta.width, y: start.y - delta.height)
    postMouse(.leftMouseDown, at: start)
    postMouse(.leftMouseDragged, at: end)
    postMouse(.leftMouseUp, at: end)
    pumpInteractionEvents(0.12)
    return true
}

@MainActor
private func postClick(at point: NSPoint) {
    let point = cgPoint(fromAppKit: point)
    postMouse(.mouseMoved, at: point)
    pumpInteractionEvents(0.03)
    postMouse(.leftMouseDown, at: point)
    pumpInteractionEvents(0.03)
    postMouse(.leftMouseUp, at: point)
    pumpInteractionEvents(0.03)
}

private func postMouse(_ type: CGEventType, at point: CGPoint) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
}

private func cgPoint(fromAppKit point: NSPoint) -> CGPoint {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
          let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: point.x, y: bounds.maxY - point.y)
    }
    let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    return CGPoint(x: bounds.minX + point.x - screen.frame.minX,
                   y: bounds.minY + screen.frame.maxY - point.y)
}

@MainActor
private func pumpInteractionEvents(_ seconds: TimeInterval = 0.4) {
    let deadline = Date(timeIntervalSinceNow: seconds)
    repeat {
        if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.01),
                                       inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    } while Date() < deadline
}

private func interactionTestRepetitions() -> Int {
    guard let value = ProcessInfo.processInfo.environment["WIXELS_INTERACTION_REPETITIONS"],
          let repetitions = Int(value) else { return 100 }
    return max(1, min(repetitions, 100))
}

private extension NSRect {
    var center: NSPoint { .init(x: midX, y: midY) }
}
