# Install the Cynaberii extension pack

This pack must match your Wixels version. It contains the 12 Cynaberii widgets and
the Cynaberii theme; it is not a standalone app.

1. Quit Wixels.
2. Extract `Wixels-Cynaberii-X.Y.Z-arm64.zip`.
3. Copy the contents of its `plugins/` folder to `~/.config/wixels/plugins/` and its
   `themes/` folder to `~/.config/wixels/themes/`. Create those folders if needed.
4. Clear the download quarantine on the copied files. The pack is ad-hoc signed and
   not notarized, so Gatekeeper otherwise blocks Wixels from loading the dylibs and
   the widgets stay missing.
5. Start Wixels again. Extensions load only at app launch.

For example, from the extracted folder:

```sh
mkdir -p ~/.config/wixels/plugins ~/.config/wixels/themes
cp plugins/libWidget*.dylib ~/.config/wixels/plugins/
cp themes/libTheme*.dylib ~/.config/wixels/themes/
xattr -dr com.apple.quarantine ~/.config/wixels
```

When upgrading, quit Wixels and replace both the app ZIP and this pack with assets
from the same release. There are no automatic updates. To uninstall the pack, quit
Wixels and remove its `libWidget*.dylib` and `libThemeCynaberii.dylib` files from
those two folders.
