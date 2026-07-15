# Wixels App Packaging Handoff

## Goal

Produce a locally distributable, Apple-silicon `Wixels.app` and a versioned ZIP for
personal sharing:

```sh
./package-app.sh 0.1.0
```

Outputs:

```text
dist/Wixels.app
dist/Wixels-0.1.0-arm64.zip
```

The app is ad-hoc signed. It is not Developer ID signed or notarized.

## Implementation

- `package-app.sh` validates a numeric `X.Y.Z` version before building.
- `build-plugins.sh release` builds the host, 12 bundled widget libraries, and two
  bundled theme libraries.
- Packaging happens in a temporary staging directory.
- Only Wixels-owned outputs for the requested release are replaced in `dist/`.
- `packaging/Info.plist` is copied into the bundle and its two version fields are
  replaced with the supplied version.
- The executable and all dynamic libraries remain together in
  `Wixels.app/Contents/MacOS`. This preserves the existing `@loader_path`/`@rpath`
  behavior without rewriting Mach-O load commands.
- Every dylib is ad-hoc signed first, followed by the executable and then the app.
- The ZIP is created with `ditto` to preserve macOS bundle metadata.
- `dist/` is ignored by Git.

`build-plugins.sh` now asks SwiftPM to build each distributable library product
explicitly (`Widget<Name>` or `Theme<Name>`). This avoids compiling the Stats package's
ad-hoc executable test target during optimized builds; its `@testable` import is not
valid in a normal release build.

## Runtime plugin lookup

Bundled extensions load from beside the executable:

```text
Wixels.app/Contents/MacOS/libWidget*.dylib
Wixels.app/Contents/MacOS/libTheme*.dylib
```

User-installed extensions continue to load directly from:

```text
~/.config/wixels/plugins/
~/.config/wixels/themes/
```

The rest of the user configuration remains under `~/.config/wixels`, including
`desktop.toml`. User-built extensions must use the same Swift toolchain as Wixels and
require an app restart after installation or replacement.

## Bundle metadata

The plist declares:

- Display name: `Wixels`
- Bundle identifier: `com.dwax05.wixels`
- Executable: `wixels`
- Package type: `APPL`
- Minimum macOS: `14.0`
- Accessory app: `LSUIElement = true`
- Apple Events usage description for Spotify playback control
- No icon, so macOS uses its generic application icon

## Automated verification completed

The packaging command currently performs and passes:

- Missing and malformed version rejection before any build
- Config test suite against the release executable
- Layout test suite against the release executable
- Plugin test suite against the release executable
- Exact payload count: 12 widgets and two themes
- `plutil` validation
- arm64-only validation for every packaged Mach-O
- macOS 14.0 deployment-target validation for every packaged Mach-O
- Dependency validation: only bundled `@rpath`/`@loader_path` libraries and system
  libraries/frameworks are accepted
- Inside-out ad-hoc signing
- `codesign --verify --deep --strict`
- Plugin loading from the assembled app
- ZIP extraction into a fresh temporary directory
- Signature and plugin tests against the extracted app

The last verified development artifact used version `0.1.0` and was written to
`dist/`. Generated artifacts are not tracked.

## Remaining manual verification

On a clean Apple-silicon Mac running macOS 14 or newer:

1. Extract the ZIP and move `Wixels.app` into Applications.
2. Right-click the app and choose **Open** to exercise the expected Gatekeeper flow.
3. Confirm the menu-bar item appears and no Dock icon appears.
4. Confirm all bundled widgets render.
5. Confirm an extension placed in `~/.config/wixels/plugins/` or
   `~/.config/wixels/themes/` loads after restarting Wixels.
6. Confirm configuration is read from `~/.config/wixels/desktop.toml`.
7. Confirm Quit stops the process cleanly.

## Distribution boundary

This flow is for personal sharing. Public distribution would additionally require a
Developer ID certificate, hardened-runtime decisions compatible with third-party dylib
loading, and Apple notarization. Those concerns are intentionally outside the current
packager.

## Worktree note

Packaging was implemented while unrelated source changes and documents were already
present. Those changes were preserved and are not part of this handoff's implementation.
