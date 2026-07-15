# Writing themes

A Wixels theme is a Swift package that defines a reusable visual style for a widget
suite. `themes/Cynaberii` pairs with `plugins/Cynaberii`; `themes/Macos` is reserved
for the future macOS widget suite. Themes change
colors, typography, panels, media shapes, borders, shadows, and spacing. They do not
replace widget content or move widgets.

## Start from the template

Copy the example package:

```sh
cp -R themes/Template themes/MyTheme
```

Rename `ThemeTemplate` in `Package.swift` and the source directory. Keep the dynamic
library product named `ThemeMyTheme`; the build script uses that convention.

The template is in [themes/Template](../themes/Template).

## Register a theme

The entry point creates one `ThemeDefinition`:

```swift
import WixelsKit

@_cdecl("wixels_register")
public func wixels_register(_ context: UnsafeMutableRawPointer) {
    let registrar = Unmanaged<Registrar>
        .fromOpaque(context)
        .takeUnretainedValue()

    registrar.add(ThemeDefinition(
        manifest: .init(id: "my-theme", name: "My Theme"),
        tokens: ThemeDefinition.macos.tokens
    ))
}
```

Use a stable lowercase kebab-case ID, such as `my-theme`. The display name is what
users see conceptually; the ID is what they put in `desktop.toml`.

Start by copying the macOS tokens, then change the values you want. The token set
covers semantic colors, typography, card fill/shape/border/shadow, media shape, and
spacing density. A theme should provide every token so every widget remains usable.

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

The repository build stages the result under `build/debug/themes`. Select the paired
widget suite explicitly when building a shipped theme:

```sh
WIXELS_WIDGET_SUITE=Cynaberii ./build-plugins.sh debug
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

Packaged themes belong in `Wixels.app/Contents/Resources/themes`. Wixels does not
scan the executable or SwiftPM build directories; `WIXELS_PLUGIN_ROOT` is only for
explicit source-checkout staging runs. The release packager includes the theme paired
with the selected widget suite only; it includes no theme in a host-only package.

## Compatibility and safety

Build the theme with the same Swift toolchain as Wixels. Themes run in the host
process and share WixelsKit types with it, so a broken theme can terminate Wixels.

If a theme ID is unknown or malformed, Wixels falls back to `macos`. If no global
theme is configured, `macos` is the default.
