# Wixels v0.1.0 public-beta release

## GitHub Release notes

Wixels v0.1.0 is an Apple-silicon public beta for macOS 14 or later. This release is
ad-hoc signed, not notarized, and has no automatic updates.

Download both matching assets:

- `Wixels-0.1.0-arm64.zip` — the host app.
- `Wixels-Cynaberii-0.1.0-arm64.zip` — the separately installed 12-widget Cynaberii
  pack and Cynaberii theme.

Extract the host app, move it to Applications, then right-click it, choose **Open**,
and confirm the first launch if Gatekeeper asks. Quit Wixels, extract the matching
extension pack, copy its `plugins/` and `themes/` contents into
`~/.config/wixels/plugins/` and `~/.config/wixels/themes/`, and restart Wixels.
The host starts empty by design; its menu and logs explain that extensions are loaded
separately. Upgrade by replacing both assets together; uninstall by quitting Wixels,
deleting the app, and optionally deleting the installed extensions and config.

Privacy and limitations: Wixels has no telemetry. Weather requests IP-derived
location from ipinfo.io and contacts weather providers. Media widgets use an
unsupported/private MediaRemote interface and may degrade after macOS updates.
Extensions run as trusted in-process code. Intel Macs and macOS before 14 are not
supported. Please file feedback and diagnostics in
[GitHub Issues](https://github.com/dwax05/wixels/issues).

## Release checklist

- Create and push tag `v0.1.0`.
- Run `./package-app.sh 0.1.0` and `./package-extension-pack.sh 0.1.0`.
- Verify the two ZIP checksums, `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the
  MediaRemote license in the appropriate payloads.
- On a clean macOS 14+ Apple-silicon account, extract and launch the host using the
  Gatekeeper right-click/Open flow. Verify config creation, empty-host menu guidance,
  and useful `wixels:` diagnostics.
- Install the extension pack, restart, and verify all 12 widgets plus the Cynaberii
  theme load. Test menu toggles, layout editing, config reload, palette/theme fallback,
  Weather while offline, and idle media widgets.
- Confirm any screenshots/GIFs accurately represent the beta and that the worktree
  has no accidental build artifacts before publishing both assets and these notes.
