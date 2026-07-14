// Weather — port of cynaberii-weather: a pixel sky scene + temperature + condition
// on a card pane. Observed conditions from the US NWS (weather.gov), falling back
// to open-meteo worldwide; location via ipinfo.io. All fetched natively with async
// URLSession (the python's curl spawns become URLSession calls). interval(900s).

import SwiftUI
import WixelsKit

enum WeatherKey: String, Sendable { case clear, night, cloud, rain, snow, storm, fog }

struct WeatherInfo: Equatable, Sendable {
    var key: WeatherKey
    var cond: String
    var tempF: Int?          // °F, nil when unknown — formatted at draw

    static let unknown = WeatherInfo(key: .cloud, cond: "--", tempF: nil)
}

/// Fetches weather over the network; caches location + station in memory across
/// ticks. Called serially by the scheduler (every 15 min), so plain mutation is safe.
final class WeatherSource: DataSource, @unchecked Sendable {
    private var loc: (lat: String, lon: String)?
    private var station: String?
    private let ua = "cynaberii-weather (wixels)"

    func read() async -> WeatherInfo {
        guard let (lat, lon) = await location() else { return .unknown }
        var found = await nws(lat, lon)
        if found == nil { found = openMeteoInfo(from: await openMeteo(lat, lon)) }
        guard var info = found else { return .unknown }
        if info.key == .clear, Self.isNight() { info.key = .night }
        return info
    }

    // MARK: fetch helpers

    private func json(_ url: String, userAgent: Bool = false) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u); req.timeoutInterval = 8
        if userAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func location() async -> (String, String)? {
        if let loc { return loc }
        guard let u = URL(string: "https://ipinfo.io/loc"),
              let (data, _) = try? await URLSession.shared.data(from: u),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.contains(",") else { return nil }
        let parts = text.split(separator: ",")
        guard parts.count >= 2 else { return nil }
        let l = (String(parts[0]), String(parts[1]))
        loc = l
        return l
    }

    // MARK: NWS (primary)

    private func nwsStation(_ lat: String, _ lon: String) async -> String? {
        if let station { return station }
        guard let pt = await json("https://api.weather.gov/points/\(lat),\(lon)", userAgent: true) as? [String: Any],
              let props = pt["properties"] as? [String: Any],
              let stationsURL = props["observationStations"] as? String,
              let st = await json(stationsURL, userAgent: true) as? [String: Any],
              let feats = st["features"] as? [[String: Any]], let f0 = feats.first,
              let fp = f0["properties"] as? [String: Any],
              let id = fp["stationIdentifier"] as? String else { return nil }
        station = id
        return id
    }

    private func nws(_ lat: String, _ lon: String) async -> WeatherInfo? {
        guard let st = await nwsStation(lat, lon),
              let obs = await json("https://api.weather.gov/stations/\(st)/observations/latest", userAgent: true) as? [String: Any],
              let props = obs["properties"] as? [String: Any],
              let desc = props["textDescription"] as? String, !desc.isEmpty,
              let tempObj = props["temperature"] as? [String: Any],
              let tc = tempObj["value"] as? Double else { return nil }
        let f = Int((tc * 9 / 5 + 32).rounded())
        return WeatherInfo(key: Self.classify(desc), cond: desc, tempF: f)
    }

    // MARK: open-meteo (fallback)

    private func openMeteo(_ lat: String, _ lon: String) async -> [String: Any]? {
        await json("https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                   + "&current=temperature_2m,weather_code&temperature_unit=fahrenheit") as? [String: Any]
    }

    private func openMeteoInfo(from data: [String: Any]?) -> WeatherInfo? {
        guard let data, let cur = data["current"] as? [String: Any],
              let code = cur["weather_code"] as? Int,
              let temp = cur["temperature_2m"] as? Double else { return nil }
        let (key, cond) = Self.wmo[code] ?? (.cloud, "Unknown")
        return WeatherInfo(key: key, cond: cond, tempF: Int(temp.rounded()))
    }

    // MARK: classify

    private static func classify(_ desc: String) -> WeatherKey {
        let s = desc.lowercased()
        if s.contains("thunder") { return .storm }
        if ["snow", "sleet", "flurr", "ice", "blizzard"].contains(where: s.contains) { return .snow }
        if ["rain", "shower", "drizzle"].contains(where: s.contains) { return .rain }
        if ["fog", "mist", "haze", "smoke"].contains(where: s.contains) { return .fog }
        if ["cloud", "overcast"].contains(where: s.contains) { return .cloud }
        if ["clear", "fair", "sunny"].contains(where: s.contains) { return .clear }
        return .cloud
    }

    static func isNight() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 || h >= 19
    }

    // open-meteo WMO code → (key, label)
    static let wmo: [Int: (WeatherKey, String)] = [
        0: (.clear, "Clear"), 1: (.clear, "Mainly Clear"), 2: (.cloud, "Partly Cloudy"),
        3: (.cloud, "Overcast"), 45: (.fog, "Fog"), 48: (.fog, "Rime Fog"),
        51: (.rain, "Drizzle"), 53: (.rain, "Drizzle"), 55: (.rain, "Drizzle"),
        56: (.rain, "Freezing Drizzle"), 57: (.rain, "Freezing Drizzle"),
        61: (.rain, "Rain"), 63: (.rain, "Rain"), 65: (.rain, "Heavy Rain"),
        66: (.rain, "Freezing Rain"), 67: (.rain, "Freezing Rain"),
        80: (.rain, "Showers"), 81: (.rain, "Showers"), 82: (.rain, "Heavy Showers"),
        71: (.snow, "Snow"), 73: (.snow, "Snow"), 75: (.snow, "Heavy Snow"),
        77: (.snow, "Snow Grains"), 85: (.snow, "Snow Showers"), 86: (.snow, "Snow Showers"),
        95: (.storm, "Thunderstorm"), 96: (.storm, "Thunderstorm"), 99: (.storm, "Thunderstorm"),
    ]
}

struct Weather: Wixel {
    let source: WeatherSource

    static let kind = "weather"

    /// Default placement + wiring for the desktop config. See Registry.swift.
    static func spec() -> WidgetSpec {
        WidgetSpec(kind: kind,
            defaultPlacement: .init(anchor: .topRight, offset: .init(width: 0, height: -60),
                                    size: .init(width: 130, height: 150), align: .trailing),
            build: { _, _ in erase(Weather(source: WeatherSource())) })
    }
    static let refresh: RefreshPolicy = .interval(900)   // 15 min; data effectively cached
    static let px: CGFloat = 5

    // icon sprites (12 wide). S sun · C cloud · M moon · B bolt
    static let sun: Sprite = [
        "............", "..S..SS..S..", "...SSSSSS...", "...SSSSSS...", "..SSSSSSSS..",
        "..SSSSSSSS..", "...SSSSSS...", "...SSSSSS...", "..S..SS..S..", "............",
    ]
    static let cloud: Sprite = [
        "............", "....CCCC....", "..CCCCCCCC..", ".CCCCCCCCCC.",
        "CCCCCCCCCCCC", ".CCCCCCCCCC.", "............", "............",
    ]
    static let moon: Sprite = [
        "...MMMM.....", "..MMMMMM....", ".MMMM.......", ".MMM........",
        ".MMM........", ".MMMM.......", "..MMMMMM....", "...MMMM.....",
    ]
    static let bolt: Sprite = [
        "............", "............", "............", "............", "............",
        "....BB......", "...BB.......", "..BBBB......", "....BB......", "...BB.......",
    ]

    func sample() async -> WeatherInfo { await source.read() }
    func render(_ s: WeatherInfo, _ p: Palette) -> some View { WeatherView(info: s, p: p) }
}

private struct WeatherView: View {
    let info: WeatherInfo
    let p: Palette

    var body: some View {
        let accent = p.c(4).color, grey = p.c(8).color, ink = p.foreground.color
        let sage = p.c(6).color
        let pal: [Character: Color] = ["S": accent, "C": grey, "M": ink, "B": accent]
        let px = Weather.px
        let sceneW = 12 * px, sceneH = 10 * px
        let k = info.key
        let showCloud: Set<WeatherKey> = [.cloud, .rain, .snow, .storm, .fog]

        return VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: sceneW, height: sceneH)
                if k == .clear { PixelStrip(frames: [Weather.sun], px: px, palette: pal) }
                if k == .night { PixelStrip(frames: [Weather.moon], px: px, palette: pal) }
                if showCloud.contains(k) { PixelStrip(frames: [Weather.cloud], px: px, palette: pal) }
                if k == .rain { Precip(color: sage, snow: false, w: sceneW, px: px) }
                if k == .snow { Precip(color: ink, snow: true, w: sceneW, px: px) }
                if k == .storm {
                    Flash { PixelStrip(frames: [Weather.bolt], px: px, palette: pal) }
                }
                if k == .fog { fogBars(grey, px: px).offset(y: 6 * px) }
            }
            Text(info.tempF.map { "\($0)°F" } ?? "--").font(.pixel(16)).foregroundColor(accent)
            Text(info.cond).font(.pixel(9)).foregroundColor(sage)
                .frame(maxWidth: 12 * px + 20).multilineTextAlignment(.center)
        }
        .fixedSize()
        .pane(p)
    }

    private func fogBars(_ color: Color, px: CGFloat) -> some View {
        VStack(spacing: px) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(color).frame(width: 11 * px, height: px).opacity(0.6)
            }
        }
    }
}

/// Falling precipitation drops overlaid on the cloud (rain streaks / round snow).
private struct Precip: View {
    let color: Color
    let snow: Bool
    let w: CGFloat
    let px: CGFloat

    var body: some View {
        let n = 4
        let dur = snow ? 1.6 : 0.8
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ForEach(0..<n, id: \.self) { i in
                let left = 8 + CGFloat(i) * (10 * px) / CGFloat(n)
                let delay = Double(i) / Double(n) * dur
                let phase = (((t - delay) / dur).truncatingRemainder(dividingBy: 1) + 1)
                    .truncatingRemainder(dividingBy: 1)
                let fall = CGFloat(phase) * (5 * px)
                Group {
                    if snow {
                        Circle().fill(color).frame(width: px, height: px)
                    } else {
                        Rectangle().fill(color).frame(width: max(1, px / 2), height: px * 1.5)
                    }
                }
                .offset(x: left, y: 5 * px + fall)
                .opacity(phase < 0.9 ? 1 : max(0, 1 - (phase - 0.9) / 0.1))
            }
        }
    }
}

/// Storm bolt flash: mostly dim with a brief bright flash, ~2.5s cycle.
private struct Flash<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t / 2.5).truncatingRemainder(dividingBy: 1)
            content().opacity((0.92...0.98).contains(phase) ? 1 : 0.15)
        }
    }
}
