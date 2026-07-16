#!/usr/bin/env bash
# Build one widget suite and its paired theme suite into build/<config>.
#
# Usage: WIXELS_WIDGET_SUITE=Cynaberii ./build-plugins.sh [debug|release]
#        ./build-plugins.sh clean
#
# WIXELS_WIDGET_SUITE is deliberately opt-in. An unset suite stages no widgets
# or themes, which keeps a future suite from being combined with this one by
# accident. WIXELS_PLUGIN_SELECTION and WIXELS_THEME_SELECTION can narrow the
# selected suite after it has been chosen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ "${1:-}" = "clean" ]; then
    rm -rf "$ROOT/build"
    find "$ROOT/plugins" "$ROOT/themes" -type d -name .build -prune -exec rm -rf {} +
    echo "==> clean"
    exit 0
fi

CONFIG="${1:-debug}"
SUITE="${WIXELS_WIDGET_SUITE-}"
PLUGIN_SELECTION="${WIXELS_PLUGIN_SELECTION-__all__}"
THEME_SELECTION="${WIXELS_THEME_SELECTION-__all__}"

DEST="$ROOT/build/$CONFIG"
PLUGIN_DEST="$DEST/plugins"
THEME_DEST="$DEST/themes" # legacy flat-theme staging is kept empty for compatibility
mkdir -p "$PLUGIN_DEST" "$THEME_DEST"
rm -rf "$PLUGIN_DEST"
mkdir -p "$PLUGIN_DEST"
rm -f "$THEME_DEST"/*.dylib

# System-wide now-playing reads use the bundled MediaRemote adapter through
# Apple's entitled /usr/bin/perl. It is deliberately a resource, never linked
# into WixelsKit, because the entitlement belongs to the system process.
ADAPTER_SOURCE="$ROOT/Vendor/MediaRemoteAdapter"
ADAPTER_BUILD="$ROOT/build/mediaremote-adapter/$CONFIG"
ADAPTER_FRAMEWORK="$DEST/MediaRemoteAdapter.framework"
ADAPTER_SCRIPT="$DEST/mediaremote-adapter.pl"
[ "$CONFIG" = "debug" ] && ADAPTER_BUILD_TYPE="Debug" || ADAPTER_BUILD_TYPE="Release"
[ -f "$ADAPTER_SOURCE/CMakeLists.txt" ] || {
    echo "error: MediaRemoteAdapter submodule is missing; run git submodule update --init --recursive" >&2
    exit 2
}
cmake -S "$ADAPTER_SOURCE" -B "$ADAPTER_BUILD" -DCMAKE_BUILD_TYPE="$ADAPTER_BUILD_TYPE" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build "$ADAPTER_BUILD" --target MediaRemoteAdapter
rm -rf "$ADAPTER_FRAMEWORK"
/bin/cp -R "$ADAPTER_BUILD/MediaRemoteAdapter.framework" "$ADAPTER_FRAMEWORK"
/bin/cp -f "$ADAPTER_SOURCE/bin/mediaremote-adapter.pl" "$ADAPTER_SCRIPT"
chmod +x "$ADAPTER_SCRIPT"
codesign --force --deep --sign - "$ADAPTER_FRAMEWORK"

selected() {
    local name="$1" selection="$2"
    [ "$selection" = "__all__" ] && return 0
    [ -z "$selection" ] || case ",$selection," in *",$name,"*) return 0;; esac
    return 1
}

install_dylib() {
    local source="$1"
    local destination="$2/$(basename "$source")"
    local temporary="$destination.installing"
    mkdir -p "$2"
    /bin/cp -f "$source" "$temporary"
    codesign --force --sign - "$temporary"
    /bin/mv -f "$temporary" "$destination"
}

if [ -z "$SUITE" ]; then
    [ "$PLUGIN_SELECTION" = "__all__" ] || echo "warning: widget selection ignored without WIXELS_WIDGET_SUITE"
    [ "$THEME_SELECTION" = "__all__" ] || echo "warning: theme selection ignored without WIXELS_WIDGET_SUITE"
else
    SUITE_ROOT="$ROOT/plugins/$SUITE"
    THEME_ROOT="$ROOT/themes/$SUITE"
    [ -d "$SUITE_ROOT" ] || { echo "error: unknown widget suite '$SUITE'" >&2; exit 2; }
    [ -d "$THEME_ROOT" ] || { echo "error: no paired theme suite for '$SUITE'" >&2; exit 2; }

    while IFS= read -r manifest; do
        dir="$(dirname "$manifest")"
        name="$(basename "$dir")"
        [ "$name" = "Support" ] && continue
        selected "$name" "$PLUGIN_SELECTION" || continue
        echo "==> building plugin: $SUITE/$name"
        swift build --package-path "$dir" -c "$CONFIG" --product "Widget$name"
        for dylib in "$dir/.build/$CONFIG"/libWidget*.dylib; do install_dylib "$dylib" "$PLUGIN_DEST/$SUITE"; done
    done < <(find "$SUITE_ROOT" -mindepth 2 -maxdepth 2 -name Package.swift -print | sort)

    name="$SUITE"
    if selected "$name" "$THEME_SELECTION"; then
        echo "==> building theme: $name"
        swift build --package-path "$THEME_ROOT" -c "$CONFIG" --product "Theme$name"
        for dylib in "$THEME_ROOT/.build/$CONFIG"/libTheme*.dylib; do install_dylib "$dylib" "$PLUGIN_DEST/$SUITE"; done
    fi
    if [ -f "$SUITE_ROOT/wixels-package.json" ]; then
        /bin/cp -f "$SUITE_ROOT/wixels-package.json" "$PLUGIN_DEST/$SUITE/wixels-package.json"
    fi
fi

# Widget dylibs link the same dynamic WixelsKit as the host. Refresh the default
# host before validation so a newly added shared-kit API cannot be tested against
# yesterday's release binary. An explicit WIXELS_HOST remains caller-controlled.
if [ -n "$SUITE" ] && [ -z "${WIXELS_HOST:-}" ]; then
    echo "==> refreshing host for plugin ABI validation"
    swift build -c "$CONFIG"
fi

HOST="${WIXELS_HOST:-$ROOT/.build/$CONFIG/wixels}"
if [ -x "$HOST" ] && [ -n "$SUITE" ]; then
    echo "==> validating staged extensions with $HOST"
    WIXELS_PLUGIN_ROOT="$DEST" WIXELS_WIDGET_SUITE="$SUITE" "$HOST" --plugin-tests
else
    echo "==> no selected suite or no host; skipping runtime plugin validation"
fi

echo "==> staged $(find "$PLUGIN_DEST" -name 'libWidget*.dylib' | wc -l | tr -d ' ') plugin(s) into $PLUGIN_DEST"
echo "==> staged $(find "$PLUGIN_DEST" -name 'libTheme*.dylib' | wc -l | tr -d ' ') theme(s) into $PLUGIN_DEST"
