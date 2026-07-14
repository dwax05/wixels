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
swift build -c "$CONFIG" --scratch-path build
DEST="$ROOT/build/$CONFIG"

for dir in plugins/*/; do
    name="$(basename "$dir")"
    # Template is the author example (copy it to make your own), not a shipped widget.
    [ "$name" = "Template" ] && continue
    echo "==> building plugin: $name"
    swift build --package-path "$dir" -c "$CONFIG" --scratch-path "build/plugins/$name"
    cp "build/plugins/$name/$CONFIG"/libWidget*.dylib "$DEST"/
done

echo "==> installed $(ls "$DEST"/libWidget*.dylib | wc -l | tr -d ' ') plugin(s) into $DEST"
echo "    footprint: $(du -sh build | cut -f1)   run: ./build/$CONFIG/wixels"
