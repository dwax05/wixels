import SwiftUI
import WixelsKit
import MacosWidgetPresentation
struct NativeStatsSample: Equatable, Sendable { let stats: StatsInfo; let network: ConnectivityInfo }
struct NativeStats: ThemeableWixel {
 let source: StatsSource; let connectivity = ConnectivitySource(); static let kind = "stats"; static let refresh: RefreshPolicy = .interval(20)
 static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .bottomRight, offset: .init(width: -24, height: 32), size: .init(width: 220, height: 170), align: .trailing, sizing: .fitContent), previews: [.init("Normal", sample: .init(stats: .init(cpu: 32, mem: 61, battery: 82, charging: false, plugged: false), network: .init(connected: true, label: "Studio Wi-Fi"))), .init("Offline", sample: .init(stats: .init(cpu: 0, mem: 0, battery: 0, charging: false, plugged: false), network: .init(connected: false, label: "Offline")))]) { s, _ in .init(source: .init(cpu: s.cpu)) } }
 func sample() async -> NativeStatsSample { async let stats = source.read(); async let network = connectivity.read(); return await .init(stats: stats, network: network) }
 func render(_ s: NativeStatsSample, _ theme: ThemeContext) -> some View { NativeCard(theme: theme) { VStack(alignment: .leading, spacing: 9) { NativeHeader("System Status", symbol: "chart.bar", theme: theme); NativeStatusRow(symbol: "cpu", title: "CPU", value: "\(s.stats.cpu)%", theme: theme); NativeStatusRow(symbol: "memorychip", title: "Memory", value: "\(s.stats.mem)%", theme: theme); NativeStatusRow(symbol: s.stats.charging ? "battery.100.bolt" : "battery.100", title: "Battery", value: "\(s.stats.battery)%", theme: theme); NativeStatusRow(symbol: s.network.connected ? "wifi" : "wifi.slash", title: "Network", value: s.network.label, theme: theme) } } }
}
