// wixels — entry point.
//
// A native macOS desktop-widget agent replacing the cynaberii Übersicht widgets.
// The whole app is: build a host, mount widgets, run. Everything else (windows,
// desktop layer, palette, scheduling, occlusion) lives behind WidgetHost.
//
// Run:  cd ~/Developer/wixels && swift run
// Quit: Ctrl-C.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: WidgetHost!

    func applicationDidFinishLaunching(_ note: Notification) {
        let music = MusicMonitor()          // one shared reader for pet + now-playing
        let cpu = CPUSource()               // one shared CPU sampler for pet + stats
        host = WidgetHost(palette: PaletteStore())
        host
            // sys box (wifi + disk jar) top-left; now-playing cassette bottom-left
            .mount(SysBox(source: SysSource()), anchor: .topLeft,
                   offset: .init(width: 40, height: -60), size: .init(width: 180, height: 120))
            .mount(NowPlaying(monitor: music), anchor: .bottomLeft,
                   offset: .init(width: 12, height: 36), size: .init(width: 320, height: 96))
            // snail overlay rides the sys box perimeter — window covers the box +
            // margins; offset so the crawl path sits just outside the box (tune to fit).
            .mount(DiskSnail(disk: DiskSource()), anchor: .topLeft,
                   offset: .init(width: -3, height: -30),
                   size: .init(width: DiskSnail.Crawl.containerW, height: DiskSnail.Crawl.containerH))
            // cat perched on the now-playing card's top-right corner (JS: pet sat on
            // the nowplaying card). cat box 72×96 (extra headroom for notes).
            .mount(CatPet(source: PetSource(cpu: cpu, music: music)), anchor: .bottomLeft,
                   offset: .init(width: 224, height: 116), size: .init(width: 92, height: 106))
            // growing plant — click to water; mid-left (Übersicht top:300 left:70)
            .mount(Plant(), anchor: .topLeft,
                   offset: .init(width: 40, height: -220), size: .init(width: 120, height: 130))
            // quotes speech bubble — click to reroll (Übersicht bottom:210 left:320)
            .mount(Quotes(source: QuoteSource()), anchor: .bottomLeft,
                   offset: .init(width: 300, height: 90), size: .init(width: 250, height: 150))
            // tree frog — hangs behind the clock, head poking out below. Mounted
            // BEFORE the clock so the clock (same window level) orders in front and
            // hides the frog's body. Click/auto-poke shoves it down out of hiding.
            .mount(Frog(source: FrogSource()), anchor: .topCenter,
                   offset: .init(width: 0, height: -136), size: .init(width: 100, height: 200))
            // pixel clock — top-centre (Übersicht top:90, centred). zBoost keeps it
            // above the frog even after a click, so it always hides the frog's body.
            .mount(PixelClock(), anchor: .topCenter,
                   offset: .init(width: 0, height: -70), size: .init(width: 220, height: 120), zBoost: 1)
            // soft-stats card (CPU plant + memory soil + battery heart) bottom-right
            .mount(Stats(source: StatsSource(cpu: cpu)), anchor: .bottomRight,
                   offset: .init(width: 0, height: 36), size: .init(width: 220, height: 150), align: .trailing)
            // owl perched above the stats card — click to blink (Übersicht right:66 bottom:205)
            .mount(Owl(source: OwlSource()), anchor: .bottomRight,
                   offset: .init(width: 0, height: 150), size: .init(width: 90, height: 70))
            // weather — pixel sky + temp, top-right (Übersicht top:80 right:60)
            .mount(Weather(source: WeatherSource()), anchor: .topRight,
                   offset: .init(width: 0, height: -60), size: .init(width: 130, height: 150), align: .trailing)
            // spotify poster — album-coloured now-playing card; only shows while a
            // track is loaded (Übersicht right:60 bottom:280). Right side, mid.
            .mount(Poster(monitor: music), anchor: .topRight,
                   offset: .init(width: 0, height: -220), size: .init(width: 230, height: 460), align: .trailing)
            .run()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // no dock icon, single process
let delegate = AppDelegate()
app.delegate = delegate
app.run()
