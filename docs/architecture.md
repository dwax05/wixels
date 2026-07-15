# Architecture notes

WixelsKit is the shared contract between the host, widget suites, and theme suites.
It owns `Wixel`, `WidgetSpec`, `Registrar`, placement, scheduling, and theme
protocols. The host loader remains suite-agnostic: it loads staged or bundled
`libWidget*.dylib` and `libTheme*.dylib` files by filename.

The repository currently ships one suite, Cynaberii, containing the pixel-art widget
implementations in `plugins/Cynaberii/<Widget>` and the paired `themes/Cynaberii`
package. `themes/Macos` and the future `plugins/Macos/<Widget>` packages reserve a
separate suite. Suite selection happens before staging and packaging, so two suites
that reuse a user-facing kind can never register together accidentally.

`ThemeableWixel` remains part of the shared API for now. Separating suites is an
organizational and declarative boundary, not a rendering rewrite.
