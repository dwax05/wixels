# wixels — design

A native macOS desktop-widget system to replace the cynaberii Übersicht widgets.
One `LSUIElement` Swift agent draws pixel-art gauges/pets on the desktop layer,
recolouring live with the pywal palette. Goal vs Übersicht: kill Electron + the
node server + per-tick shell spawns; keep the modular "one folder = one widget"
authoring feel.

Design language follows the deep-module frame: a lot of behaviour behind a small
interface, placed at a clean seam, testable through that interface.

## Feasibility — settled by the spike

Proven on a real machine (macOS 15.7, Swift 6.2), see `Sources/wixels`:

- Borderless `NSWindow` pinned to `.desktopWindow` level, `.canJoinAllSpaces`,
  click-through — sits on the wallpaper behind app windows, on every Space.
- `.accessory` activation policy — single process, no dock icon, no Chromium/node.
- Live wal recolour on theme switch (the hard part).
- Continuous GPU animation via `TimelineView(.animation)`.

Not yet proven: the actual battery win (native data sources vs shell-spawn,
occlusion-pause). That's the point of the migration and still needs measuring.

### Spike gotchas already paid for

1. **Watch the file, not the directory.** pywal rewrites `~/.cache/wal/colors.json`
   *in place* (Python `open(...,'w')`, truncate+write, same inode). A directory
   kqueue only fires on add/remove/rename, so a dir watch never sees it. Watch the
   file fd with `.write/.extend`, and re-arm on `.delete/.rename` for any flow that
   atomically replaces the file.
2. **No Swift Concurrency in a DispatchSource handler.** Touching
   `Task`/`MainActor`/`assumeIsolated` from a libdispatch worker thread trips
   `swift_task_isCurrentExecutor` -> `dispatch_assert_queue_fail` (abort) on Swift 6.
   Fire the source on the `.main` queue and use plain Dispatch closures; mark the
   store `@unchecked Sendable` (safe — everything runs on main).

## Seams — which are real

Rule: one adapter means a hypothetical seam; two adapters means a real one. Only
build seams where something actually varies.

| Seam | Adapters | Verdict |
|---|---|---|
| **Widget** | disk-snail, cat-pet, clock, now-playing, thermal-frog, … | **Real** — build it |
| **DataSource** | cpu (mach), disk (statfs), battery (IOKit), nowplaying (MediaRemote) | **Real** — internal seam |
| **PaletteStore** | wal `colors.json` only | **Hypothetical** — keep concrete |
| **Placement** | static config only | **Hypothetical** — plain struct, not a seam |

`PaletteStore` has one source, so it is not a seam — but its *interface* is still
deep: it hides file-watching, in-place-write handling, JSON parsing, hex→Color,
and publishing behind `@Published var palette`. Depth without a seam.

## Widget — the external seam

The interface a widget author must satisfy. Two methods; everything else lives
behind the host. Mirrors Übersicht's `command` (data) / `render` (draw) split.

```swift
protocol Widget {
    associatedtype Sample: Equatable        // the metric (= Übersicht `command` output)
    associatedtype Content: View
    static var kind: String { get }          // stable id — debug, /tmp force-files
    static var refresh: RefreshPolicy { get }
    func sample() async -> Sample            // data source            (= command)
    @ViewBuilder func render(_ s: Sample, _ palette: Palette) -> Content   // (= render)
}

enum RefreshPolicy {
    case interval(TimeInterval)          // poll (disk, cpu)
    case push(() -> AsyncStream<Void>)   // event-driven (nowplaying via MediaRemote)
    case idleStatic                      // sample once + on palette change (battery rule)
}
```

**Deletion test.** Delete the host: every widget re-grows its own `NSWindow`,
desktop-level pinning, palette wiring, timer, and occlusion logic — N times over.
Delete the protocol: each widget hardwires its own placement + scheduling. In both
cases complexity reappears across N call sites, so both seams earn their keep.

## DataSource — internal seam, composed and injected

```swift
protocol DataSource { associatedtype Reading; func read() async -> Reading }

struct DiskSource: DataSource { func read() async -> DiskInfo { /* statfs */ } }
struct CPUSource:  DataSource { func read() async -> Double   { /* mach host_processor_info */ } }
```

A widget **accepts** its source rather than constructing it — the key testability
move (accept dependencies, don't create them):

```swift
struct DiskSnail: Widget {
    let disk: any DataSource
    func sample() async -> DiskInfo { await disk.read() }
    func render(_ s: DiskInfo, _ p: Palette) -> some View { /* pure: pixels from s + p */ }
}
```

Native sources replace the shell/python data sources one-for-one, no process spawn:
cpu/mem via `host_processor_info`/mach, disk via `statfs`, battery/thermal via
`IOKit`, now-playing via the private `MediaRemote.framework`. A single shared
sampler feeds all subscribers (as the current `_cynshared` CPU sampler does).

## Testability

- `render(_:_:)` is a **pure function** of `(Sample, Palette)` — no side effects,
  snapshot-testable directly. This is the whole reason to split sample/render.
- `sample()` takes an injected `DataSource` — feed a fake reading, assert `Sample`.
- The host scheduler is tested against a fake `Widget` — no window server needed.

## Host — the deep implementation (one place = locality)

A single `WidgetHost` owns everything the widgets don't:

- one desktop `NSWindow` per mount (borderless, `.desktopWindow`, all-Spaces, click-through);
- palette injection via `@EnvironmentObject`;
- **one shared scheduler** that coalesces all `.interval` widgets — not N timers;
- occlusion-aware pause (covered widgets stop sampling/animating);
- placement (lives here, not in the widget — a widget shouldn't know screen coords).

```swift
Host(palette: PaletteStore())
  .mount(DiskSnail(disk: DiskSource()), anchor: .topRight, offset: .init(width: -20, height: -20))
  .mount(CatPet(cpu: CPUSource()),      anchor: .bottomRight)
  .run()
```

### Open decision — type erasure

`associatedtype Sample` blocks `any Widget`. Two options:

1. **Erase at mount (chosen).** `mount()` closes over the concrete widget and
   returns an opaque `MountedWidget` exposing only `kind`, `refresh`, and
   `makeSelfUpdatingView(palette:)`. The host never sees `Sample`; the widget
   protocol stays clean and `render` stays pure.
2. **Drop the associatedtype.** Widgets emit `AnyView` + erased data. Simpler
   types, but loses the pure-`render` snapshot-test benefit.

Chose #1 — preserving the pure render seam is worth the small erasure wrapper.

## Constraints / sharp edges

- `MediaRemote` is private API — fine for a personal machine, may break on OS
  updates, not App-Store shippable. We are not shipping.
- Desktop-level window vs per-Space wallpaper on Sonoma+ can fight; test the
  window level early on the target OS (done in the spike, holds on 15.7).
- Metal shaders: porting the cava GLSL (`orion_saturn_core.frag`, …) to Metal
  Shading Language is close but not 1:1 — a later phase, not blocking.

## Migration order

1. Lock the `Widget` + `DataSource` seams by porting **two** widgets — DiskSnail
   (`idleStatic`, disk) and CatPet (`interval`, cpu). Two adapters prove both
   seams are real, and exercise static-vs-animated + two data sources.
2. Build the shared scheduler + occlusion pause; **measure battery** against the
   Übersicht baseline. This is the go/no-go for the whole migration.
3. Port remaining widgets one at a time.
4. Metal port for the cava/shader widgets.
