# Wixels v0.1.1 public-beta release

## GitHub Release notes

Wixels v0.1.1 is an Apple-silicon public beta for macOS 14 or later. This release is
ad-hoc signed, not notarized, and has no automatic updates.

New in 0.1.1: Wixels now detects quarantined extension files in `~/.config/wixels`
at launch and asks for permission to remove the quarantine, then loads the widgets
immediately — no manual `xattr` command or second restart. Declining the prompt
skips those files until the next launch.

Download both matching assets:

- `Wixels-0.1.1-arm64.zip` — the host app.
- `Wixels-Cynaberii-0.1.1-arm64.zip` — the separately installed 12-widget Cynaberii
  pack and Cynaberii theme.

Extract the host app and move it to Applications. The beta is ad-hoc signed and not
notarized, so Gatekeeper blocks the first launch: on macOS 14 right-click the app,
choose **Open**, and confirm; on macOS 15 or later dismiss the warning, then use
**System Settings > Privacy & Security > Open Anyway** (the right-click shortcut no
longer works there). Quit Wixels, extract the matching extension pack, copy its
`plugins/` and `themes/` contents into `~/.config/wixels/plugins/` and
`~/.config/wixels/themes/`, and restart Wixels — approve the quarantine prompt when
it appears. Upgrade by replacing both assets together; uninstall by quitting Wixels,
deleting the app, and optionally deleting the installed extensions and config.

Privacy and limitations: Wixels has no telemetry. Weather requests IP-derived
location from ipinfo.io and contacts weather providers. Media widgets use an
unsupported/private MediaRemote interface and may degrade after macOS updates.
Extensions run as trusted in-process code; only approve the quarantine prompt for
packs from sources you trust. Intel Macs and macOS before 14 are not supported.
Please file feedback and diagnostics in
[GitHub Issues](https://github.com/dwax05/wixels/issues).

## Release checklist

- Create and push tag `v0.1.1`.
- Run `./package-app.sh 0.1.1` and `./package-extension-pack.sh 0.1.1`.
- Verify the two ZIP checksums, `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the
  MediaRemote license in the appropriate payloads.
- On a clean macOS 14+ Apple-silicon account, extract and launch the host using the
  Gatekeeper flow for that OS (macOS 14: right-click/Open; macOS 15+: Privacy &
  Security "Open Anyway"). Verify config creation, empty-host menu guidance, and
  useful `wixels:` diagnostics.
- Install the extension pack, restart, approve the quarantine prompt, and verify all
  12 widgets plus the Cynaberii theme load in that same launch. Also verify that
  declining the prompt leaves the host empty with a log note, and that the manual
  `xattr` fallback works.
- Test menu toggles, layout editing, config reload, palette/theme fallback, Weather
  while offline, and idle media widgets.
- Confirm any screenshots/GIFs accurately represent the beta and that the worktree
  has no accidental build artifacts before publishing both assets and these notes.
