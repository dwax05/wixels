# Wixels v0.1.4 public-beta pre-release

## GitHub Release notes

Wixels v0.1.4-beta.1 is an Apple-silicon public beta pre-release for macOS 14 or
later. This release is ad-hoc signed, not notarized, and has no automatic updates.

New in 0.1.4:

- Plugin folders now appear as their own groups in the menu-bar menu, so each
  installed suite is visible and manageable as a unit.
- A themed folder owns its bundled `libTheme*.dylib`; the folder's widgets and
  theme are loaded together as one visual bundle.
- **Enable Only This Folder** switches the active visual bundle and restarts
  Wixels safely, so complete looks can be swapped in one action.
- Cynaberii's original fixed-size pixel-art widgets are restored.
- The Macos and Cynaberii suites can coexist as separate folders without their
  overlapping widget binaries mixing; when two folders provide dylibs with the
  same filename, Wixels keeps the first and logs the conflict.

Download both matching assets:

- `Wixels-0.1.4-arm64.zip` — the host app.
- `Wixels-Cynaberii-0.1.4-arm64.zip` — the separately installed 12-widget
  Cynaberii pack with its bundled theme.

Extract the host app and move it to Applications. The beta is ad-hoc signed and not
notarized, so Gatekeeper blocks the first launch: on macOS 14 right-click the app,
choose **Open**, and confirm; on macOS 15 or later dismiss the warning, then use
**System Settings > Privacy & Security > Open Anyway** (the right-click shortcut no
longer works there). Quit Wixels, extract the matching extension pack, and copy its
self-contained `plugins/` contents into `~/.config/wixels/plugins/`, preserving the
subfolders — for example the pack's `plugins/Cynaberii/` folder must arrive as
`~/.config/wixels/plugins/Cynaberii/`. There is no separate `themes/` payload: each
folder carries its own bundled theme dylib. Restart Wixels and approve the
quarantine prompt when it appears. Always install matching host and Cynaberii
extension-pack assets from the same release together; upgrade by replacing both,
and uninstall by quitting Wixels, deleting the app, and optionally deleting the
installed extensions and config.

Privacy and limitations: Wixels has no telemetry. Weather requests IP-derived
location from ipinfo.io and contacts weather providers. Media widgets use an
unsupported/private MediaRemote interface and may degrade after macOS updates.
Extensions run as trusted in-process code; only approve the quarantine prompt for
packs from sources you trust. Intel Macs and macOS before 14 are not supported.
Please file feedback and diagnostics in
[GitHub Issues](https://github.com/dwax05/wixels/issues).

## Release checklist

- Create and push tag `v0.1.4-beta.1`.
- Run `./package-app.sh 0.1.4` and `./package-extension-pack.sh 0.1.4`.
- Verify the two ZIP checksums, `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the
  MediaRemote license in the appropriate payloads.
- On a clean macOS 14+ Apple-silicon account, extract and launch the host using the
  Gatekeeper flow for that OS (macOS 14: right-click/Open; macOS 15+: Privacy &
  Security "Open Anyway"). Verify config creation, empty-host menu guidance, and
  useful `wixels:` diagnostics.
- Install the extension pack by copying `plugins/` recursively (preserving the
  `plugins/Cynaberii/` subfolder), restart, approve the quarantine prompt, and
  verify all 12 Cynaberii widgets render in their pixel-art fixed-frame form in
  that same launch.
- Verify the menu shows the folder as a group and that **Enable Only This
  Folder** persists the active folder and restarts Wixels.
- Test menu toggles, layout editing, config reload, palette/theme fallback,
  Weather while offline, and idle media widgets.
- Confirm any screenshots/GIFs accurately represent the beta and that the
  worktree has no accidental build artifacts before publishing both assets and
  these notes.
