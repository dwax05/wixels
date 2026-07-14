# wixels

Native macOS desktop widgets — pixel-art gauges and pets that live on your wallpaper,
behind your app windows. The classic theme recolours itself from an optional
[pywal](https://github.com/dylanaraps/pywal) palette; native themes follow macOS appearance.

One tiny `.accessory` process draws everything on the desktop layer (on every Space, no
dock icon, no Electron, no node server). Widgets and themes are loadable `.dylib`s, and
a single TOML file decides which widgets run, how they look, and where they live.

> Replaces the cynaberii Übersicht widget set with a native Swift agent.

## Requirements

- macOS 14+ (built and run on 15.7)
- Swift 6.2 toolchain (Xcode 16 or a matching Swift toolchain)
- Optional: [pywal](https://github.com/dylanaraps/pywal) writing
  `~/.cache/wal/colors.json` for live `cynaberii` recolouring

## Build & run

Widgets are separate Swift packages, so a plain `swift build` builds only the host. Use
the script:

```sh
./build-plugins.sh            # build host, bundled widgets, and bundled themes
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

## Widgets and themes

All twelve bundled widgets own one canonical content tree, sampling policy, interactions,
and placement. Themes are universal token packages: they change semantic colors,
typography, card fill/shape/border/shadow, and spacing density without replacing content.
`macos` uses system colors, typography, regular material, rounded cards, and automatic
light/dark adaptation. `cynaberii` uses Silkscreen, the live pywal palette, square panes,
accent borders, and offset shadows.

| kind | behavior / classic appearance |
|------|-------------------------------|
| `clock` | local time and date / blinking pixel digits |
| `stats` | CPU, memory, battery / plant, soil, and heart |
| `sys` | wifi bars + disk jar |
| `disk-snail` | a snail that crawls the box perimeter over 24h as a disk gauge |
| `pet` | a cat reacting to CPU / network / battery / music |
| `plant` | click-to-water growth that persists |
| `quotes` | a speech bubble; click to reroll |
| `frog` | thermal-reactive frog that pops out from behind the clock |
| `owl` | idle-presence gauge (awake / drowsy / asleep) |
| `weather` | pixel sky + temperature (NWS → open-meteo) |
| `nowplaying` | track state and play/pause / pixel cassette with album art |
| `poster` | a now-playing card recoloured from the album cover |

## Configuring the layout

Edit `~/.config/wixels/desktop.toml` (override the path with `WIXELS_CONFIG`). Each
`[[widget]]` block enables a widget by `kind`; delete a block to disable it. Placement
fields are optional — omit them to use the widget's built-in default. Config is read
once at launch.

One exception writes the file back: dragging a widget in the menu-bar layout editor and
saving persists its new `offset` by regenerating `desktop.toml`. Every widget block,
option, and unknown field is retained, but comments and hand-formatting are dropped.

```toml
[theme]
default = "macos" # optional: macos is also the default when this table is absent

# App-global data files (env WIXELS_COLORS / WIXELS_NOWPLAYING override these).
[paths]
colors     = "~/.cache/wal/colors.json"        # optional pywal palette for compatible themes
nowplaying = "~/.cache/wixels/nowplaying.json" # music cache your publisher writes

[[widget]]
kind = "clock"
theme = "cynaberii"      # optional per-widget override
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

Theme resolution is widget override → global default → `macos`. Unknown or malformed
IDs use `macos`. Since every theme is universal, changing themes never changes window
placement; explicit placement fields win field-by-field and Reset Layout restores the
widget's own defaults.

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

## Writing a theme

Theme dylibs provide one universal `ThemeDefinition`. Copy `themes/Template`, register a
stable lowercase-kebab-case manifest plus `ThemeTokens`, and rebuild with
`./build-plugins.sh`. User themes may be installed in `~/.config/wixels/themes/`.

```swift
registrar.add(ThemeDefinition(
    manifest: .init(id: "my-theme", name: "My Theme"),
    tokens: ThemeDefinition.macos.tokens
))
```

Theme authors never import widget sample/action types. The registrar validates IDs and
keeps the first duplicate definition. Theme packs run in-process and must use the same
Swift toolchain as the host and plugins.

## How it works

Four roles across Swift packages:

- **`WixelsKit`** — the shared dynamic ABI: `Wixel`, `ThemeableWixel`, universal theme
  tokens, the render kit, palette, data sources, placement, and registrar. Host,
  widgets, and themes all link this one runtime copy so type identity holds across
  `dlopen`.
- **`wixels`** — the host executable: desktop windows, one shared refresh scheduler,
  occlusion-aware pause, the plugin loader, and the TOML config reader.
- **`plugins/<Name>/`** — one package per widget, each a drop-in `.dylib`. The 12
  built-ins are themselves plugins.
- **`themes/<Name>/`** — universal token packages loaded as `libTheme*.dylib`.

At launch the host loads `libWidget*.dylib` from the executable directory and
`~/.config/wixels/plugins/`, plus `libTheme*.dylib` from the executable directory and
`~/.config/wixels/themes/`. It then reads `desktop.toml`, resolves tokens for each
themeable widget, and mounts the widget's canonical view. Interval widgets share a single scheduler loop;
occluded widgets stop sampling.

## Notes

Personal project, not App Store shippable. Now-playing data (title/artist/artwork) is
read from a shared cache file (`~/.cache/wixels/nowplaying.json` by default; set via
`[paths] nowplaying`) that an external music plugin publishes, since in-process
`MediaRemote` no longer works for ad-hoc binaries on recent macOS.
