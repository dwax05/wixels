#!/usr/bin/env bash
# Build only the standalone widget and theme packages. Artifacts are staged outside
# SwiftPM's package `.build` directories for copying into an app bundle or for an
# explicit source-checkout run with WIXELS_PLUGIN_ROOT.
#
# Usage: ./build-plugins.sh [debug|release]   (default: debug)
#        ./build-plugins.sh clean             (remove plugin/theme staging artifacts)
# Optional: WIXELS_PLUGIN_SELECTION=Clock,Frog WIXELS_THEME_SELECTION=Macos
#           (select packages; unset builds all non-template packages)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ "${1:-}" = "clean" ]; then
    for scratch in build plugins/*/.build themes/*/.build; do
        if [ -d "$scratch" ]; then
            echo "==> removing $scratch ($(du -sh "$scratch" | cut -f1))"
            rm -rf "$scratch"
        fi
    done
    echo "==> clean"
    exit 0
fi

CONFIG="${1:-debug}"
PLUGIN_SELECTION="${WIXELS_PLUGIN_SELECTION-__all__}"
THEME_SELECTION="${WIXELS_THEME_SELECTION-__all__}"

DEST="$ROOT/build/$CONFIG"
PLUGIN_DEST="$DEST/plugins"
THEME_DEST="$DEST/themes"
mkdir -p "$PLUGIN_DEST" "$THEME_DEST"
rm -f "$PLUGIN_DEST"/*.dylib "$THEME_DEST"/*.dylib

selected() {
    local name="$1" selection="$2"
    [ "$selection" = "__all__" ] && return 0
    [ -z "$selection" ] || case ",$selection," in *",$name,"*) return 0;; esac
    return 1
}

# Never overwrite a loaded, signed dylib in place. A running wixels process may
# still have that inode mapped; changing its pages makes macOS kill the process
# with CODESIGNING / Invalid Page. Install a signed temporary copy by atomic rename
# so existing processes keep the old inode and new launches see the new one.
install_dylib() {
    local source="$1"
    local destination="$2/$(basename "$source")"
    local temporary="$destination.installing"
    /bin/cp -f "$source" "$temporary"
    codesign --force --sign - "$temporary"
    /bin/mv -f "$temporary" "$destination"
}

for dir in plugins/*/; do
    name="$(basename "$dir")"
    # Template is the author example (copy it to make your own), not a shipped widget.
    [ "$name" = "Template" ] && continue
    selected "$name" "$PLUGIN_SELECTION" || continue
    echo "==> building plugin: $name"
    swift build --package-path "$dir" -c "$CONFIG" \
        --product "Widget$name"
    for dylib in "$dir/.build/$CONFIG"/libWidget*.dylib; do install_dylib "$dylib" "$PLUGIN_DEST"; done
done

for dir in themes/*/; do
    name="$(basename "$dir")"
    [ "$name" = "Template" ] && continue
    selected "$name" "$THEME_SELECTION" || continue
    echo "==> building theme: $name"
    swift build --package-path "$dir" -c "$CONFIG" \
        --product "Theme$name"
    for dylib in "$dir/.build/$CONFIG"/libTheme*.dylib; do install_dylib "$dylib" "$THEME_DEST"; done
done

HOST="${WIXELS_HOST:-$ROOT/.build/$CONFIG/wixels}"
if [ -x "$HOST" ] && [ "$PLUGIN_SELECTION" = "__all__" ] && [ "$THEME_SELECTION" = "__all__" ]; then
    echo "==> validating staged extensions with $HOST"
    WIXELS_PLUGIN_ROOT="$DEST" "$HOST" --plugin-tests
elif [ -x "$HOST" ]; then
    echo "==> selected extension set; skipping all-bundled runtime validation"
else
    echo "==> no host supplied; skipping runtime plugin validation"
fi

echo "==> staged $(find "$PLUGIN_DEST" -name 'libWidget*.dylib' | wc -l | tr -d ' ') plugin(s) into $PLUGIN_DEST"
echo "==> staged $(find "$THEME_DEST" -name 'libTheme*.dylib' | wc -l | tr -d ' ') theme(s) into $THEME_DEST"
