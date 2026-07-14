#!/usr/bin/env bash
# Build the wixels host + every widget plugin, then install the plugin dylibs next to
# the host executable (.build/<config>/) where PluginLoader finds them at launch.
#
# Widgets are standalone packages under plugins/<Name>/, so a plain `swift build` at the
# repo root builds ONLY the host. Run this instead to get a runnable set. Re-run after
# editing any plugin. Usage: ./build-plugins.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> building host (wixels) [$CONFIG]"
swift build -c "$CONFIG"
DEST="$ROOT/.build/$CONFIG"

for dir in plugins/*/; do
    name="$(basename "$dir")"
    # Template is the author example (copy it to make your own), not a shipped widget.
    [ "$name" = "Template" ] && continue
    echo "==> building plugin: $name"
    ( cd "$dir" && swift build -c "$CONFIG" )
    cp "$dir/.build/$CONFIG"/libWidget*.dylib "$DEST"/
done

echo "==> installed $(ls "$DEST"/libWidget*.dylib | wc -l | tr -d ' ') plugin(s) into $DEST"
echo "    run: ./.build/$CONFIG/wixels"
