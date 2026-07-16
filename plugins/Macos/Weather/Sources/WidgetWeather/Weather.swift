import SwiftUI
import Foundation
import WixelsKit
import MacosWidgetPresentation
struct NativeWeatherInfo: Equatable, Sendable { let temperature: Int?; let condition: String; let symbol: String }
final class NativeWeatherSource: DataSource, @unchecked Sendable {
    func read() async -> NativeWeatherInfo {
        guard let locURL = URL(string: "https://ipinfo.io/loc"), let (locData, _) = try? await URLSession.shared.data(from: locURL), let loc = String(data: locData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ","), loc.count == 2, let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(loc[0])&longitude=\(loc[1])&current=temperature_2m,weather_code&temperature_unit=fahrenheit"), let (data, _) = try? await URLSession.shared.data(from: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let current = json["current"] as? [String: Any], let temp = current["temperature_2m"] as? Double else { return .init(temperature: nil, condition: "Weather unavailable", symbol: "cloud.slash") }
        let code = current["weather_code"] as? Int ?? 3
        let state: (String, String) = switch code { case 0, 1: ("Clear", "sun.max.fill"); case 45, 48: ("Fog", "cloud.fog.fill"); case 51...67, 80...82: ("Rain", "cloud.rain.fill"); case 71...77, 85, 86: ("Snow", "cloud.snow.fill"); case 95...99: ("Storm", "cloud.bolt.rain.fill"); default: ("Cloudy", "cloud.fill") }
        return .init(temperature: Int(temp.rounded()), condition: state.0, symbol: state.1)
    }
}
struct NativeWeather: ThemeableWixel {
    let source: NativeWeatherSource; static let kind = "weather"; static let refresh: RefreshPolicy = .interval(900)
    static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .topRight, offset: .init(width: -24, height: -48), size: .init(width: 180, height: 120), align: .trailing, sizing: .fitContent), namespace: "macos", previews: [.init("Current", sample: .init(temperature: 72, condition: "Partly Cloudy", symbol: "cloud.sun.fill")), .init("Unavailable", sample: .init(temperature: nil, condition: "Weather unavailable", symbol: "cloud.slash"))]) { _, _ in .init(source: .init()) } }
    func sample() async -> NativeWeatherInfo { await source.read() }
    func render(_ s: NativeWeatherInfo, _ theme: ThemeContext) -> some View { NativeCard(theme: theme) { HStack(spacing: 14) { Image(systemName: s.symbol).font(.system(size: 38)).foregroundStyle(theme.color(.accent)).accessibilityHidden(true); VStack(alignment: .leading, spacing: 4) { NativeMetric(s.temperature.map { "\($0)°" } ?? "—", label: s.condition, theme: theme); Text("Current conditions").font(theme.font(.label)).foregroundStyle(theme.color(.secondary)) } } .accessibilityElement(children: .combine) } }
}
