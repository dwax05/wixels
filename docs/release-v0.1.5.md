# Wixels v0.1.5 public-beta pre-release

## GitHub release notes

Wixels v0.1.5-beta.1 is an Apple-silicon public beta pre-release for macOS 14 or
later. This release is ad-hoc signed, not notarized, and has no automatic updates.

New in 0.1.5:

- Plugin collections are now described consistently as **packages** throughout the
  menu and documentation.
- Put a theme and a selected set of widget dylibs in one immediate package folder,
  such as `~/.config/wixels/plugins/mypackage/`; that folder appears as its own
  submenu under the `w` menu.
- **Load Only This Package** persists the selected package and relaunches Wixels so
  its widgets and bundled theme load as one set.

For example, a small Cynaberii pet package may contain:

```text
~/.config/wixels/plugins/mypackage/
  libThemeCynaberii.dylib
  libWidgetPet.dylib
```

Download the host app plus at least one extension pack:

- `Wixels-0.1.5-arm64.zip` — the host app.
- `Wixels-Cynaberii-0.1.5-arm64.zip` — the separately installed 12-widget
  Cynaberii pack with its bundled theme.
- `Wixels-Macos-0.1.5-arm64.zip` — the 6-widget native-look macOS pack with its
  bundled theme.

Extract the host app and move it to Applications. The beta is ad-hoc signed and not
notarized, so Gatekeeper blocks the first launch: on macOS 14 right-click the app,
choose **Open**, and confirm; on macOS 15 or later dismiss the warning, then use
**System Settings > Privacy & Security > Open Anyway**. Quit Wixels, extract each
extension pack you want, and copy its self-contained `plugins/` contents into
`~/.config/wixels/plugins/`, preserving subfolders. Each pack installs as its own
package submenu, so **Load Only This Package** switches between complete looks. There is no separate `themes/`
payload: each package carries its theme dylib beside its widget dylibs. Restart
Wixels and approve the quarantine prompt when it appears.

## Release checklist

- Commit the v0.1.5 package-menu changes and push the release branch.
- Run `./package-app.sh 0.1.5`, `./package-extension-pack.sh 0.1.5`, and
  `./package-extension-pack.sh 0.1.5 Macos`.
- Verify the three ZIP checksums and their expected licenses/notices.
- On a clean macOS 14+ Apple-silicon account, verify the host’s first-launch and
  Gatekeeper flow, then install the extension pack and approve its quarantine prompt.
- Create `~/.config/wixels/plugins/mypackage/` containing
  `libThemeCynaberii.dylib` and `libWidgetPet.dylib`; restart Wixels and verify that
  `mypackage` is a submenu and **Load Only This Package** leaves only the pet widget
  active with the Cynaberii theme.
- Create and push tag `v0.1.5-beta.1`, then create a GitHub **pre-release** using
  this document’s GitHub release notes and upload all three ZIPs.
