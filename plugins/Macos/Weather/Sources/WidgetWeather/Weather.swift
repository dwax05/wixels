import SwiftUI
import Foundation
import WixelsKit
import MacosWidgetPresentation
struct NativeWeatherInfo: Equatable, Sendable { let temperature: Int?; let condition: String; let symbol: String }

/// Location persists to disk (`~/.config/wixels/weather-location.txt`, shared with
/// the Cynaberii widget) so a restart doesn't re-hit ipinfo.io's tight unauthenticated
/// rate limit — a desktop widget's location is effectively static.
final class NativeWeatherSource: DataSource, @unchecked Sendable {
    private var loc: (String, String)?
    private let ipinfoToken: String?
    private static var cachePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/wixels/weather-location.txt")
    }

    init(ipinfoToken: String? = nil) { self.ipinfoToken = ipinfoToken }

    private static func parseLocation(_ text: String) -> (String, String)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 2, Double(parts[0]) != nil, Double(parts[1]) != nil else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private func location() async -> (String, String)? {
        if let loc { return loc }
        if let cached = try? String(contentsOfFile: Self.cachePath, encoding: .utf8),
           let parsed = Self.parseLocation(cached) { loc = parsed; return parsed }
        let endpoint = ipinfoToken.map { "https://ipinfo.io/loc?token=\($0)" } ?? "https://ipinfo.io/loc"
        guard let locURL = URL(string: endpoint),
              let (locData, locResponse) = try? await URLSession.shared.data(from: locURL),
              (locResponse as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: locData, encoding: .utf8),
              let parsed = Self.parseLocation(text) else { return nil }
        loc = parsed
        let dir = (Self.cachePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? "\(parsed.0),\(parsed.1)".write(toFile: Self.cachePath, atomically: true, encoding: .utf8)
        return parsed
    }

    func read() async -> NativeWeatherInfo {
        guard let (lat, lon) = await location(),
              let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=fahrenheit"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double else { return .init(temperature: nil, condition: "Weather unavailable", symbol: "cloud.slash") }
        let code = current["weather_code"] as? Int ?? 3
        let state: (String, String) = switch code { case 0, 1: ("Clear", "sun.max.fill"); case 45, 48: ("Fog", "cloud.fog.fill"); case 51...67, 80...82: ("Rain", "cloud.rain.fill"); case 71...77, 85, 86: ("Snow", "cloud.snow.fill"); case 95...99: ("Storm", "cloud.bolt.rain.fill"); default: ("Cloudy", "cloud.fill") }
        return .init(temperature: Int(temp.rounded()), condition: state.0, symbol: state.1)
    }
}
struct NativeWeather: ThemeableWixel {
    let source: NativeWeatherSource; static let kind = "weather"; static let refresh: RefreshPolicy = .interval(900)
    static func spec() -> ThemedWidgetSpec { .init(widget: Self.self, defaultPlacement: .init(anchor: .topRight, offset: .init(width: -24, height: -48), size: .init(width: 180, height: 120), align: .trailing, sizing: .fitContent), namespace: "macos", previews: [.init("Current", sample: .init(temperature: 72, condition: "Partly Cloudy", symbol: "cloud.sun.fill")), .init("Unavailable", sample: .init(temperature: nil, condition: "Weather unavailable", symbol: "cloud.slash"))]) { _, options in .init(source: .init(ipinfoToken: options.string("ipinfoToken"))) } }
    func sample() async -> NativeWeatherInfo { await source.read() }
    func render(_ s: NativeWeatherInfo, _ theme: ThemeContext) -> some View { NativeCard(theme: theme) { HStack(spacing: 14) { Image(systemName: s.symbol).font(.system(size: 38)).foregroundStyle(theme.color(.accent)).accessibilityHidden(true); VStack(alignment: .leading, spacing: 4) { NativeMetric(s.temperature.map { "\($0)°" } ?? "—", label: s.condition, theme: theme); Text("Current conditions").font(theme.font(.label)).foregroundStyle(theme.color(.secondary)) } } .accessibilityElement(children: .combine) } }
}
