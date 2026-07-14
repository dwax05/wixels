# wixels

Native macOS desktop widgets — pixel-art gauges and pets that live on your wallpaper,
behind your app windows, and recolour themselves live with your [pywal](https://github.com/dylanaraps/pywal)
palette.

One tiny `.accessory` process draws everything on the desktop layer (on every Space, no
dock icon, no Electron, no node server). Each widget is a **standalone plugin** — a
`.dylib` the host loads at launch — and a single TOML file decides which widgets run,
where, and with what options. Adding or rearranging a widget never recompiles the core.

> Replaces the cynaberii Übersicht widget set with a native Swift agent.

## Requirements

- macOS 14+ (built and run on 15.7)
- Swift 6.2 toolchain (Xcode 16 or a matching Swift toolchain)
- [pywal](https://github.com/dylanaraps/pywal) writing `~/.cache/wal/colors.json` (for
  live recolouring)

## Build & run

Widgets are separate Swift packages, so a plain `swift build` builds only the host. Use
the script:

```sh
./build-plugins.sh            # build the host + every widget plugin into ./build
./build/debug/wixels          # run (foreground; Ctrl-C to quit)
```

All build output stays under `./build`. Other commands:

```sh
./build-plugins.sh release    # optimized build
./build-plugins.sh clean      # remove ./build entirely
pkill -x wixels               # stop a running instance (never `pkill -f`)
```

On first run wixels writes a default layout to `~/.config/wixels/desktop.toml` with
every widget enabled. Widgets sit behind your app windows — bring your desktop forward
(or minimize windows) to see them.

## Widgets

| kind | what it is |
|------|------------|
| `clock` | HH:MM pixel digits, blinking colon, date |
| `stats` | CPU-wilt plant + memory soil + battery heart |
| `sys` | wifi bars + disk jar |
| `disk-snail` | a snail that crawls the box perimeter over 24h as a disk gauge |
| `pet` | a cat reacting to CPU / network / battery / music |
| `plant` | click-to-water growth that persists |
| `quotes` | a speech bubble; click to reroll |
| `frog` | thermal-reactive frog that pops out from behind the clock |
| `owl` | idle-presence gauge (awake / drowsy / asleep) |
| `weather` | pixel sky + temperature (NWS → open-meteo) |
| `nowplaying` | a pixel cassette with album art; click toggles play/pause |
| `poster` | a now-playing card recoloured from the album cover |

## Configuring the layout

Edit `~/.config/wixels/desktop.toml` (override the path with `WIXELS_CONFIG`). Each
`[[widget]]` block enables a widget by `kind`; delete a block to disable it. Placement
fields are optional — omit them to use the widget's built-in default. Config is read
once at launch.

```toml
# App-global data files (env WIXELS_COLORS / WIXELS_NOWPLAYING override these).
[paths]
colors     = "~/.cache/wal/colors.json"        # pywal palette — recolours everything
nowplaying = "~/.cache/wixels/nowplaying.json" # music cache your publisher writes

[[widget]]
kind = "clock"
anchor = "topCenter"     # topLeft topRight bottomLeft bottomRight center topCenter
offset = [0, -70]        # [x, y]
size   = [220, 120]      # [w, h]
zBoost = 1               # optional; raises stacking among same-level widgets
align  = "trailing"      # optional

[[widget]]
kind = "disk-snail"
  [widget.options]       # optional per-widget settings
  path = "/"             # volume the disk gauge measures

[[widget]]
kind = "quotes"
  [widget.options]
  path = "~/.config/wixels/quotes.json"   # JSON array of quote strings
```

Block order = mount order = stacking order among widgets that share a window level (the
frog is listed before the clock so the clock draws in front and hides the frog's body).

Paths resolve in the order **env var → `[paths]`/`[widget.options]` → built-in default**,
so a missing config key just falls back to the default. `[paths]` holds app-global files
(shared by several widgets); per-widget files live in that widget's `[widget.options]`.

## Writing your own widget

A widget is a small Swift package producing a `libWidget<Name>.dylib`. Copy the example:

```sh
cp -r plugins/Template plugins/MyThing
```

Then edit `plugins/MyThing/Sources/WidgetMyThing/` — implement `spec()` (registration,
defaults, and construction), `sample()` (fetch data), and `render(_:_:)` (construct the
view from your sample + palette) — build with `./build-plugins.sh`, and add a
`[[widget]] kind = "my-thing"` block to your TOML.
You never touch the host: it supplies the window, desktop pinning, palette, scheduler,
and occlusion pause. Passive widgets should render deterministically from the supplied
sample and palette. Interactive widgets may keep local UI state or invoke explicit
user actions, but should not perform scheduled sampling from `render`. See
`plugins/Template/` for the fully-commented starting point.

Third-party plugins can be dropped into `~/.config/wixels/plugins/` and loaded without
rebuilding the core — build them with the **same Swift toolchain** as wixels (Swift has
no stable cross-version ABI). Plugins run in-process, so a crashing plugin takes down the
host.

## How it works

Three kinds of Swift package:

- **`WixelsKit`** — a cross-package *dynamic* library that is the plugin ABI: the `Wixel`
  protocol, the pixel render kit, the palette, the data sources, and the config/registrar
  types. Host and every plugin link this one shared copy, so type identity holds across
  `dlopen`.
- **`wixels`** — the host executable: desktop windows, one shared refresh scheduler,
  occlusion-aware pause, the plugin loader, and the TOML config reader.
- **`plugins/<Name>/`** — one package per widget, each a drop-in `.dylib`. The 12
  built-ins are themselves plugins.

At launch the host loads every `libWidget*.dylib`, reads `desktop.toml`, and mounts each
enabled widget at its placement. Interval widgets share a single scheduler loop; occluded
widgets stop sampling (to stay light on battery).

## Notes

Personal project, not App Store shippable. Now-playing data (title/artist/artwork) is
read from a shared cache file (`~/.cache/wixels/nowplaying.json` by default; set via
`[paths] nowplaying`) that an external music plugin publishes, since in-process
`MediaRemote` no longer works for ad-hoc binaries on recent macOS.
