import SwiftUI
import WixelsKit
import MacosWidgetPresentation

struct ClockSample: Equatable, Sendable { var now: Date; var agenda: AgendaSnapshot }
struct NativeClock: ThemeableWixel {
    let calendar: CalendarSource
    static let kind = "clock"; static let refresh: RefreshPolicy = .interval(60)
    static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .topCenter, offset: .init(width: 0, height: -44), size: .init(width: 270, height: 150), sizing: .fitContent), previews: [.init("Upcoming", sample: .init(now: .now, agenda: .init(authorization: .authorized, items: [.init(title: "Design review", date: .now.addingTimeInterval(3600))]))), .init("Calendar permission", sample: .init(now: .now, agenda: .init(authorization: .denied)))]) { _, _ in Self(calendar: .init()) } }
    func sample() async -> ClockSample { .init(now: .now, agenda: await calendar.read()) }
    func render(_ s: ClockSample, _ theme: ThemeContext) -> some View { NativeCard(theme: theme) { VStack(alignment: .leading, spacing: 10) { NativeHeader("Today", symbol: "calendar", theme: theme); NativeMetric(s.now.formatted(date: .omitted, time: .shortened), label: s.now.formatted(date: .complete, time: .omitted), theme: theme); agenda(s.agenda, theme) } } }
    @MainActor @ViewBuilder private func agenda(_ agenda: AgendaSnapshot, _ theme: ThemeContext) -> some View { switch agenda.authorization { case .authorized: if let item = agenda.items.first { NativeStatusRow(symbol: "calendar.badge.clock", title: item.title, value: item.date.formatted(date: .omitted, time: .shortened), theme: theme) } else { NativeStateView(.empty, message: "No more events today", theme: theme) }; case .notDetermined: NativeStateView(.permission, message: "Calendar access is needed", theme: theme); case .denied, .restricted: NativeStateView(.permission, message: "Calendar access is unavailable", theme: theme) } }
}
