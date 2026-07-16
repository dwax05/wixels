import SwiftUI
import WixelsKit
import MacosWidgetPresentation
struct NativeReminders: ThemeableWixel {
 let source: RemindersSource; static let kind = "reminders"; static let refresh: RefreshPolicy = .interval(15); static let interactive = true
 static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .topLeft, offset: .init(width: 28, height: -64), size: .init(width: 260, height: 160), align: .topLeading, sizing: .fitContent), previews: [.init("Due next", sample: .init(authorization: .authorized, items: [.init(title: "Send release notes", date: .now), .init(title: "Water plants", date: .now.addingTimeInterval(86_400))])), .init("Empty", sample: .init(authorization: .authorized)), .init("Permission", sample: .init(authorization: .denied))]) { _, _ in .init(source: .init()) } }
 func sample() async -> AgendaSnapshot { await source.read() }
 func render(_ s: AgendaSnapshot, _ theme: ThemeContext) -> some View {
     NativeRemindersView(snapshot: s, theme: theme, complete: { await source.complete(id: $0) },
         reload: { await source.read() })
 }
}

private struct NativeRemindersView: View {
    let snapshot: AgendaSnapshot
    let theme: ThemeContext
    let complete: @Sendable (String) async -> Bool
    let reload: @Sendable () async -> AgendaSnapshot
    @State private var completed = Set<String>()
    @State private var reloadedSnapshot: AgendaSnapshot?

    private var displayedSnapshot: AgendaSnapshot { reloadedSnapshot ?? snapshot }

    var body: some View {
        NativeCard(theme: theme) {
            VStack(alignment: .leading, spacing: 9) {
                NativeHeader("Reminders", symbol: "checklist", theme: theme)
                content
            }
        }
        .onChange(of: snapshot) { _, _ in reloadedSnapshot = nil }
    }

    @ViewBuilder private var content: some View {
        if displayedSnapshot.authorization == .authorized {
            let items = displayedSnapshot.items.filter { !completed.contains($0.id) }
            if items.isEmpty {
                NativeStateView(.empty, message: "Nothing due next", theme: theme)
            } else {
                ForEach(items) { item in
                    Button { markComplete(item.id) } label: {
                        NativeStatusRow(symbol: "circle", title: item.title,
                            value: item.date == .distantFuture ? "Later" : item.date.formatted(.dateTime.weekday(.abbreviated)),
                            theme: theme)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityHint("Marks this reminder complete")
                }
            }
        } else {
            NativeStateView(.permission, message: "Reminders access is needed", theme: theme)
        }
    }

    private func markComplete(_ id: String) {
        Task {
            guard await complete(id) else { return }
            completed.insert(id)
            reloadedSnapshot = await reload()
        }
    }
}
