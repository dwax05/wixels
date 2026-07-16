# Writing themes

A Wixels theme is a Swift package that defines a reusable visual style for widgets.
Themes are independently publishable and may be shipped beside a widget pack. Themes change
colors, typography, panels, media shapes, borders, shadows, and spacing. They do not
replace widget content or move widgets.

## Start from the template

Copy the example package:

```sh
cp -R themes/Template themes/MyTheme
mkdir -p plugins/MyTheme
cp plugins/Template/wixels-package.json plugins/MyTheme/wixels-package.json
```

Rename `ThemeTemplate` in `Package.swift` and the source directory. Keep the dynamic
library product named `ThemeMyTheme`; the build script uses that convention.

The template is in [themes/Template](../themes/Template).

Edit the copied manifest so its `id` is your package ID and its sole library entry
is `{ "file": "libThemeMyTheme.dylib", "themeID": "my-theme" }`. A theme-only
package has no widget source directories; the manifest is still placed at
`plugins/MyTheme/wixels-package.json` so the packager has one package root.

## Register a theme

The entry point creates one complete `ThemeDefinition`:

```swift
import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>
        .fromOpaque(context)
        .takeUnretainedValue()

    registrar.add(ThemeDefinition(
        manifest: .init(id: "my-theme", name: "My Theme"),
        tokens: /* define every semantic color, font, and recipe here */,
        defaultPalette: /* define every palette value here */
    ))
}
```

Use a stable lowercase kebab-case ID, such as `my-theme`. The display name is what
users see conceptually; the ID is what they put in `desktop.toml`.

Start by copying the complete template definition, then change the values you want. The
token set covers semantic colors, typography, card fill/shape/border/shadow, media
shape, and spacing density. A theme must provide a complete `defaultPalette` (background,
foreground, and color0–color15): it is used for any palette component the user's
`[colors]` TOML and pywal file leave unspecified.

Themes are universal: they do not import widget sample types and cannot change a
widget's placement or behavior.

## Build and install

Build the standalone widget/theme packages, including bundled themes:

```sh
./build-plugins.sh debug
```

Or build only your package:

```sh
swift build --package-path themes/MyTheme
```

The repository build stages a package's theme under `build/debug/plugins/<Package>`.
Select the package explicitly when building a shipped theme:

```sh
WIXELS_WIDGET_SUITE=MyPackage ./build-plugins.sh debug
```

For a user
install, copy `libThemeMyTheme.dylib` to `~/.config/wixels/themes/`, then select it in
`~/.config/wixels/desktop.toml`:

```toml
[theme]
default = "my-theme"
```

You can override the theme for one widget:

```toml
[[widget]]
kind = "clock"
theme = "my-theme"
```

Restart Wixels after installing a new theme library. Changing the configuration
reloads the selected theme for already-installed libraries.

To ship a theme with a small, selectable widget set, place both dylibs in the same
immediate package folder, for example `~/.config/wixels/plugins/mypackage/`. That
folder becomes a menu submenu; **Load Only This Package** activates its widgets and
theme together.

The host app contains no packaged themes. Put a distributable theme in a package
folder with a `wixels-package.json`, then publish it with
`./package-extension-pack.sh X.Y.Z MyPackage`.

## Compatibility and safety

Build the theme with the same Swift toolchain as Wixels. Themes run in the host
process and share WixelsKit types with it, so a broken theme can terminate Wixels.

Every distributable package needs a `wixels-package.json` beside its dylibs. It
declares a schema version, its WixelsKit compatibility range, and every dylib it
ships; Wixels validates it before loading code. Unknown theme IDs fall back to the
loaded `macos` theme. If that required default is not loaded, themed widgets are not
mounted and Wixels logs the missing package.
