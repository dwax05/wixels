# Writing widgets

This guide is for people who want to add a new Wixels widget. A widget is a small
Swift package that builds to a dynamic library. Wixels loads it at launch and makes it
available in `desktop.toml`.

## Start from the template

From the Wixels repository, copy the generic template into a package directory and
give the package a stable ID:

```sh
mkdir -p plugins/MyPackage
cp -R plugins/Template plugins/MyPackage/MyThing
cp plugins/Template/wixels-package.json plugins/MyPackage/wixels-package.json
```

Rename `WidgetTemplate` in `Package.swift`, the source directory, and the Swift files
to match your widget. Keep the library product named `WidgetMyThing`; the build script
uses that convention. Edit the package-root `wixels-package.json` with your package
ID and the renamed widget dylib/kind before publishing.

The template is in [plugins/Template](../plugins/Template). It contains a working
widget, not just an empty scaffold.

## The three pieces

The main widget type conforms to `Wixel`. Suite widgets that should work with any
installed theme instead conform to `ThemeableWixel` and use `ThemedWidgetSpec`.

```swift
struct MyThing: Wixel {
    static let kind = "my-thing"
    static let refresh: RefreshPolicy = .interval(60)

    static func spec() -> WidgetSpec {
        WidgetSpec(
            kind: kind,
            defaultPlacement: .init(
                anchor: .center,
                size: .init(width: 150, height: 70)
            ),
            build: { services, options in
                erase(MyThing())
            }
        )
    }

    func sample() async -> String {
        "hello"
    }

    @MainActor
    func render(_ sample: String, _ palette: Palette) -> some View {
        Text(sample).foregroundColor(palette.c(4).color).pane(palette)
    }
}
```

`spec()` registers the widget and declares its default size and position. `sample()`
gets data off the main actor. `render` turns the latest sample into SwiftUI content.

Placements are `.fixed` by default: `size` is the permanent window size, which
preserves compatibility with existing plugins. First-party widgets normally opt
into `sizing: .fitContent`; then `size` is only the nonzero fallback used before
the first render, and the host resizes the real window to the rendered content.
The configured anchor controls how a later content-size change grows: top/bottom
anchors preserve that vertical edge, left/right anchors preserve that horizontal
edge, and center anchors remain centered. Do not use alignment expansion to pad a
fit-content widget—the window is already its visible boundary.

Keep `render` deterministic: it should draw from its arguments and avoid I/O or
scheduled work. Put data fetching in `sample()`. Wixels supplies scheduling, desktop
windows, palette updates, and pauses sampling when a widget is fully covered.

Use `.idleStatic` for content that only needs one sample. Use `.interval(n)`
for data that should refresh periodically. Set `static var interactive = true` when
the widget needs to receive clicks; otherwise it remains click-through wallpaper.

## Register the widget

The plugin entry point passes a registrar to the host:

```swift
@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>
        .fromOpaque(context)
        .takeUnretainedValue()
    registrar.add(MyThing.spec())
}
```

The template already contains this in `Register.swift`. Register every widget shipped
by the package.

## Build and install

Build the standalone widget packages while developing:

```sh
./build-plugins.sh debug
```

To build only your widget:

```sh
swift build --package-path plugins/MyPackage/MyThing
```

The repository build stages the result under `build/debug/plugins`. Select the suite
explicitly when building the repository:

```sh
WIXELS_WIDGET_SUITE=MyPackage ./build-plugins.sh debug
```

To run the host
from the checkout against that staging area:

```sh
swift build
WIXELS_PLUGIN_ROOT="$PWD/build/debug" ./.build/debug/wixels
```

For a user install, copy `libWidgetMyThing.dylib` to a package folder such as
`~/.config/wixels/plugins/MyCollection/`; that folder becomes its menu submenu. A
package can also include a `libTheme*.dylib`, so users can load just that widget set
and its matching theme from **Load Only This Package**.
Packaged widgets are installed under `~/.config/wixels/plugins/<Package>/`; the
host app contains no extension packs. Include a `wixels-package.json` beside the
dylibs, then publish with `./package-extension-pack.sh X.Y.Z <Package>`. Add the
widget to the layout with its stable existing kind:

```toml
[[widget]]
kind = "my-thing"
```

Restart Wixels after installing a new library. Configuration edits reload live, but
the host does not unload and reload dynamic libraries during a run.

## Options and data sources

Values under a widget's `[widget.options]` table arrive in the `build` closure:

```toml
[[widget]]
kind = "my-thing"

  [widget.options]
  label = "My desktop"
```

Read options there and pass them into your widget. For system data, prefer the shared
data sources in WixelsKit when one fits. A widget can also implement its own reader in
`sample()`.

## Compatibility and safety

Build the widget with the same Swift toolchain as Wixels. Swift does not promise a
stable cross-version ABI, and the plugin shares WixelsKit types with the host.

Plugins run in Wixels' process. Treat a plugin like trusted local code: a crash or
fatal error in a plugin can terminate Wixels.

## Native suite conventions

The first-party `Macos` suite keeps one package per widget beneath
`plugins/Macos`. Its suite-local `MacosWidgetPresentation` module provides `NativeCard`,
`NativeHeader`, `NativeMetric`, `NativeStatusRow`, and `NativeStateView`—for the
standard native card language. They resolve colors, typography, materials, spacing,
and accessibility from `ThemeContext`; custom SwiftUI composition remains welcome
where it makes a widget clearer.

Register deterministic fixtures with the optional `previews:` argument to
`ThemedWidgetSpec`. A preview carries a named sample and is rendered by the exact
same `render` method as production, so it must not need network, EventKit, or other
machine state. Run a staged suite with `WIXELS_WIDGET_SUITE=Macos
./build-plugins.sh debug`, then open the developer-only gallery with
`WIXELS_PLUGIN_ROOT="$PWD/build/debug" ./.build/debug/wixels --gallery`.
