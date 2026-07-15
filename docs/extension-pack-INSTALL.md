# Install the Cynaberii extension pack

This pack must match your Wixels version. It contains the 12 Cynaberii widgets and
the Cynaberii theme; it is not a standalone app.

1. Quit Wixels.
2. Extract `Wixels-Cynaberii-X.Y.Z-arm64.zip`.
3. Copy the contents of its `plugins/` folder to `~/.config/wixels/plugins/` while
   keeping the `Cynaberii/` subfolder. Its theme is bundled in that folder.
4. Start Wixels again. Extensions load only at app launch. Because this pack was
   downloaded, macOS quarantines the copied files; Wixels detects that and asks for
   permission to remove the quarantine, then loads the widgets immediately.

If you decline that prompt, or run Wixels 0.1.0 (which has no prompt), clear the
quarantine manually and restart Wixels. For example, from the extracted folder:

```sh
mkdir -p ~/.config/wixels/plugins
cp -R plugins/. ~/.config/wixels/plugins/
xattr -dr com.apple.quarantine ~/.config/wixels
```

When upgrading, quit Wixels and replace both the app ZIP and this pack with assets
from the same release. There are no automatic updates. To uninstall the pack, quit
Wixels and remove its `plugins/Cynaberii/` folder.
