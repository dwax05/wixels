# Wixels

Wixels puts small pixel-art widgets on your macOS desktop. Clocks, system gauges,
pets, plants, weather, music, and other ambient details live behind your windows,
so your desktop can be useful without becoming another app to manage.

Wixels is a native macOS app. It has no dock icon, runs from the menu bar, and uses
your desktop wallpaper as its canvas.

## What you get

The bundled widgets include:

- `clock` — time and date
- `stats` — CPU, memory, and battery
- `sys` — Wi-Fi and disk status
- `weather` — local conditions and temperature
- `nowplaying` — the current track with play/pause controls
- `poster` — album-art artwork for the current track
- `disk-snail` — a snail that measures disk usage
- `pet` — a cat that reacts to system activity
- `plant` — a plant you can water
- `quotes` — a clickable quote bubble
- `frog` — a temperature-reactive frog
- `owl` — an idle/awake presence indicator

There are two bundled looks:

- `macos` uses system colors, materials, and automatic light/dark appearance.
- `cynaberii` uses a pixel-art palette, square panels, and optional live colors from
  [pywal](https://github.com/dylanaraps/pywal).

## Requirements

- macOS 14 or newer
- Apple silicon for the packaged app
- Swift 6.2 when building from source

## Install and run

For a packaged build, extract the ZIP and move `Wixels.app` to Applications. The
personal-sharing build is ad-hoc signed, so macOS may ask you to right-click the app,
choose **Open**, and confirm the first launch.

If you are running from this repository, build the app and its bundled content with:

```sh
./build-plugins.sh
./.build/debug/wixels
```

Wixels starts in the foreground from a source build. Press `Ctrl-C` to stop it.

On first launch, Wixels creates `~/.config/wixels/desktop.toml` and enables the
bundled widgets. The widgets are behind your windows, so minimize or move a window
aside to see them.

## The menu-bar menu

Click the `w` icon in the menu bar to:

- show or hide individual widgets for the current session;
- turn on **Edit Layout**, then drag widgets into place;
- choose **Reset Layout** to restore each widget's default position; or
- quit Wixels.

Layout changes made by dragging are saved to `desktop.toml`. Menu-bar visibility
toggles are temporary and return to the configuration on the next launch.

## Customize your desktop

Edit `~/.config/wixels/desktop.toml` in any text editor. Wixels watches this file and
reloads it after you save, so you can change the layout, theme, widget options, and
data paths without restarting.

The smallest widget entry is:

```toml
[[widget]]
kind = "clock"
```

Delete a widget entry to disable it. The order of entries controls the stacking order
when widgets overlap. You can set a global theme or override it for one widget:

```toml
[theme]
default = "cynaberii"

[[widget]]
kind = "clock"
theme = "macos"
anchor = "topCenter"
offset = [0, -70]
size = [220, 120]
```

Useful placement fields are `anchor`, `offset = [x, y]`, `size = [width, height]`,
`zBoost`, and `align`. Omit a field to keep the widget's built-in default.

Widget-specific settings go in `[widget.options]`. For example:

```toml
[[widget]]
kind = "disk-snail"

  [widget.options]
  path = "/"

[[widget]]
kind = "quotes"

  [widget.options]
  path = "~/.config/wixels/quotes.json"
```

The optional `[paths]` table configures shared data files:

```toml
[paths]
colors = "~/.cache/wal/colors.json"
nowplaying = "~/.cache/wixels/nowplaying.json"
```

Environment variables take precedence over these paths: `WIXELS_CONFIG` selects a
different layout file, `WIXELS_COLORS` selects a palette file, and
`WIXELS_NOWPLAYING` selects the music cache.

## Add your own

Wixels is designed to be extended with drop-in widgets and themes. You do not need to
change the host app to create either one.

- [Writing widgets](docs/writing-widgets.md)
- [Writing themes](docs/writing-themes.md)
- [Architecture notes](DESIGN.md)

Third-party widgets go in `~/.config/wixels/plugins/`, and themes go in
`~/.config/wixels/themes/`. Build them with the same Swift toolchain as Wixels. They
run inside the app, so a broken extension can take down the host.

## Build a release package

To create an Apple-silicon app and ZIP for personal sharing:

```sh
./package-app.sh 0.1.0
```

The output is written to `dist/Wixels.app` and
`dist/Wixels-0.1.0-arm64.zip`.

## Troubleshooting

If widgets do not appear, bring the desktop forward or check that their entries are
enabled in the menu-bar menu. If a configuration edit is invalid, Wixels falls back
to its default layout.

Wixels reads now-playing information from a cache file rather than directly from
MediaRemote. Set `[paths].nowplaying` or `WIXELS_NOWPLAYING` if your music publisher
uses a different location.
