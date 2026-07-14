#!/usr/bin/env bash
# Build the wixels host + every widget plugin, keeping ALL build output under the single
# top-level ./build tree (host in build/<config>/, each plugin's scratch in
# build/plugins/<Name>/), then install the plugin dylibs next to the host executable
# (build/<config>/) where PluginLoader finds them at launch.
#
# Widgets are standalone packages under plugins/<Name>/, so a plain `swift build` at the
# repo root builds ONLY the host. Run this instead to get a runnable set. Re-run after
# editing any plugin.
#
# Usage: ./build-plugins.sh [debug|release]   (default: debug)
#        ./build-plugins.sh clean             (remove ./build entirely)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Keep .build a symlink to ./build so plain `swift build` and this script share the
# one visible scratch tree. A fresh clone (or a stray plain build) leaves a real
# .build dir; that drift is what clobbers the module cache — see the host note below.
if [ ! -L .build ]; then
    if [ -e .build ]; then rm -rf .build; fi
    ln -s build .build
fi

if [ "${1:-}" = "clean" ]; then
    if [ -d build ]; then
        echo "==> removing ./build ($(du -sh build | cut -f1))"
        rm -rf build
    fi
    echo "==> clean"
    exit 0
fi

CONFIG="${1:-debug}"

echo "==> building host (wixels) [$CONFIG]"
# Host uses the default scratch dir (.build, a symlink to ./build) so plain
# `swift build` and this script share ONE literal path — mixing `.build` and
# `build` for the same dir clobbers the module cache (corrupt Foundation PCM).
swift build -c "$CONFIG"
DEST="$ROOT/build/$CONFIG"

# Never overwrite a loaded, signed dylib in place. A running wixels process may
# still have that inode mapped; changing its pages makes macOS kill the process
# with CODESIGNING / Invalid Page. Install a signed temporary copy by atomic rename
# so existing processes keep the old inode and new launches see the new one.
install_dylib() {
    local source="$1"
    local destination="$DEST/$(basename "$source")"
    local temporary="$destination.installing"
    /bin/cp -f "$source" "$temporary"
    codesign --force --sign - "$temporary"
    /bin/mv -f "$temporary" "$destination"
}

for dir in plugins/*/; do
    name="$(basename "$dir")"
    # Template is the author example (copy it to make your own), not a shipped widget.
    [ "$name" = "Template" ] && continue
    echo "==> building plugin: $name"
    swift build --package-path "$dir" -c "$CONFIG" --scratch-path "build/plugins/$name"
    for dylib in "build/plugins/$name/$CONFIG"/libWidget*.dylib; do install_dylib "$dylib"; done
done

for dir in themes/*/; do
    name="$(basename "$dir")"
    [ "$name" = "Template" ] && continue
    echo "==> building theme: $name"
    swift build --package-path "$dir" -c "$CONFIG" --scratch-path "build/themes/$name"
    for dylib in "build/themes/$name/$CONFIG"/libTheme*.dylib; do install_dylib "$dylib"; done
done

# Static signature verification does not catch the invalid-page failure above.
# Exercise the real dlopen path so a broken artifact fails this build immediately.
"$DEST/wixels" --plugin-tests

echo "==> installed $(ls "$DEST"/libWidget*.dylib | wc -l | tr -d ' ') plugin(s) into $DEST"
echo "==> installed $(ls "$DEST"/libTheme*.dylib | wc -l | tr -d ' ') theme(s) into $DEST"
echo "    footprint: $(du -sh build | cut -f1)   run: ./build/$CONFIG/wixels"
