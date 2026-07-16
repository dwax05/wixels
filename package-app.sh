#!/usr/bin/env bash
# Build and package an Apple-silicon Wixels.app for personal distribution.
# Usage: ./package-app.sh X.Y.Z
# Set WIXELS_BUNDLED_WIDGET_SUITE only for private all-in-one builds; public
# releases use the separate package-extension-pack.sh archive instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"

if [ "$#" -ne 1 ] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ./package-app.sh X.Y.Z (numeric semantic version, for example 0.1.0)" >&2
    exit 2
fi

cd "$ROOT"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wixels-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

APP="$STAGING/Wixels.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
PLUGINS="$RESOURCES/plugins"
THEMES="$RESOURCES/themes"
ADAPTER_FRAMEWORK="$RESOURCES/MediaRemoteAdapter.framework"
ADAPTER_SCRIPT="$RESOURCES/mediaremote-adapter.pl"
PLIST="$APP/Contents/Info.plist"
RELEASE="$ROOT/.build/release"
BUNDLED_SUITE="${WIXELS_BUNDLED_WIDGET_SUITE-}"

if [ -n "$BUNDLED_SUITE" ] && [ ! -d "$ROOT/plugins/$BUNDLED_SUITE" ]; then
    echo "error: unknown widget suite '$BUNDLED_SUITE'" >&2
    exit 2
fi

echo "==> building Wixels $VERSION"
swift build -c release
WIXELS_WIDGET_SUITE="$BUNDLED_SUITE" \
    "$ROOT/build-plugins.sh" release

echo "==> running release test suites"
"$RELEASE/wixels" --config-tests
if [ -n "$BUNDLED_SUITE" ]; then
    WIXELS_PLUGIN_ROOT="$ROOT/build/release" "$RELEASE/wixels" --layout-tests
else
    echo "==> no widgets bundled; skipping layout tests"
fi

PLUGIN_BUILD="$ROOT/build/release/plugins"
THEME_BUILD="$ROOT/build/release/themes"
shopt -s nullglob
widget_dylibs=("$PLUGIN_BUILD"/*/libWidget*.dylib)
theme_dylibs=("$PLUGIN_BUILD/$BUNDLED_SUITE"/libTheme*.dylib)
expected_plugins=0
expected_themes=0
if [ -n "$BUNDLED_SUITE" ]; then
    # Support is a shared library package, not a widget; build-plugins.sh skips it.
    expected_plugins="$(find "$ROOT/plugins/$BUNDLED_SUITE" -mindepth 2 -maxdepth 2 -name Package.swift ! -path '*/Support/*' | wc -l | tr -d ' ')"
    expected_themes=1
fi
if [ "${#widget_dylibs[@]}" -ne "$expected_plugins" ]; then
    echo "error: expected $expected_plugins selected widget dylibs in $PLUGIN_BUILD" >&2
    exit 1
fi
if [ "${#theme_dylibs[@]}" -ne "$expected_themes" ]; then
    echo "error: expected $expected_themes selected theme dylibs in $THEME_BUILD" >&2
    exit 1
fi

mkdir -p "$MACOS" "$PLUGINS" "$THEMES"
cp "$ROOT/packaging/Info.plist" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -lint "$PLIST"

cp "$RELEASE/wixels" "$RELEASE/libWixelsKit.dylib" "$MACOS/"
if [ "$expected_plugins" -gt 0 ]; then
    mkdir -p "$PLUGINS/$BUNDLED_SUITE"
    cp "${widget_dylibs[@]}" "$PLUGINS/$BUNDLED_SUITE/"
    cp "${theme_dylibs[@]}" "$PLUGINS/$BUNDLED_SUITE/"
    if [ ! -f "$PLUGIN_BUILD/$BUNDLED_SUITE/wixels-package.json" ]; then
        echo "error: $BUNDLED_SUITE build output is missing wixels-package.json" >&2
        exit 1
    fi
    cp "$PLUGIN_BUILD/$BUNDLED_SUITE/wixels-package.json" "$PLUGINS/$BUNDLED_SUITE/"
fi
cp -R "$ROOT/build/release/MediaRemoteAdapter.framework" "$ADAPTER_FRAMEWORK"
cp "$ROOT/build/release/mediaremote-adapter.pl" "$ADAPTER_SCRIPT"
cp "$ROOT/Vendor/MediaRemoteAdapter/LICENSE" "$RESOURCES/MediaRemoteAdapter-LICENSE"
# The adapter's CMake project builds universal binaries; personal Wixels
# packages are Apple-silicon-only, matching the host and extension payload.
lipo -thin arm64 "$ADAPTER_FRAMEWORK/MediaRemoteAdapter" -output "$ADAPTER_FRAMEWORK/MediaRemoteAdapter.arm64"
mv "$ADAPTER_FRAMEWORK/MediaRemoteAdapter.arm64" "$ADAPTER_FRAMEWORK/MediaRemoteAdapter"

if [ "$(find "$PLUGINS" -maxdepth 2 -name 'libWidget*.dylib' | wc -l | tr -d ' ')" -ne "$expected_plugins" ] ||
   [ "$(find "$PLUGINS" -maxdepth 2 -name 'libTheme*.dylib' | wc -l | tr -d ' ')" -ne "$expected_themes" ]; then
    echo "error: bundled extension payload is not in the resource folders" >&2
    exit 1
fi

echo "==> validating Apple-silicon payload"
for binary in "$MACOS/wixels" "$MACOS"/*.dylib "$PLUGINS"/*/*.dylib "$THEMES"/*.dylib "$ADAPTER_FRAMEWORK/MediaRemoteAdapter"; do
    if [ "$(lipo -archs "$binary")" != "arm64" ]; then
        echo "error: $(basename "$binary") is not arm64-only" >&2
        exit 1
    fi
    if ! vtool -show-build "$binary" | grep -Eq 'minos[[:space:]]+14(\.0+)?$'; then
        echo "error: $(basename "$binary") does not target macOS 14.0" >&2
        exit 1
    fi

    while IFS= read -r dependency; do
        case "$dependency" in
            /System/*|/usr/lib/*) ;;
            @rpath/*|@loader_path/*)
                [ "$dependency" = "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" ] && continue
                dependency_name="$(basename "$dependency")"
                if [ ! -e "$MACOS/$dependency_name" ] && ! find "$PLUGINS" -name "$dependency_name" -print -quit | grep -q . && [ ! -e "$THEMES/$dependency_name" ]; then
                    echo "error: $(basename "$binary") depends on missing $dependency" >&2
                    exit 1
                fi
                ;;
            *)
                echo "error: $(basename "$binary") has unexpected dependency $dependency" >&2
                exit 1
                ;;
        esac
    done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
done

echo "==> signing app"
for dylib in "$MACOS"/*.dylib "$PLUGINS"/*/*.dylib "$THEMES"/*.dylib; do
    codesign --force --sign - "$dylib"
done
codesign --force --sign - "$MACOS/wixels"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$expected_plugins" -gt 0 ]; then
    echo "==> testing packaged plugins"
    mkdir -p "$STAGING/plugin-test-home"
    HOME="$STAGING/plugin-test-home" "$MACOS/wixels" --plugin-tests
else
    echo "==> no bundled extensions selected; skipping plugin runtime test"
fi

ZIP="$STAGING/Wixels-$VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> verifying archive round trip"
EXTRACTED="$STAGING/extracted"
mkdir -p "$EXTRACTED"
ditto -x -k "$ZIP" "$EXTRACTED"
codesign --verify --deep --strict --verbose=2 "$EXTRACTED/Wixels.app"
if [ "$expected_plugins" -gt 0 ]; then
    HOME="$STAGING/plugin-test-home" "$EXTRACTED/Wixels.app/Contents/MacOS/wixels" --plugin-tests
fi

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Wixels.app"
rm -f "$ROOT/dist/Wixels-$VERSION-arm64.zip"
mv "$APP" "$ROOT/dist/Wixels.app"
mv "$ZIP" "$ROOT/dist/Wixels-$VERSION-arm64.zip"

if [ "$(find "$ROOT/dist/Wixels.app/Contents/Resources/plugins" -maxdepth 2 -name 'libWidget*.dylib' | wc -l | tr -d ' ')" -ne "$expected_plugins" ]; then
    echo "error: packaged app lost its widget payload" >&2
    exit 1
fi

echo "==> packaged dist/Wixels.app"
echo "==> packaged dist/Wixels-$VERSION-arm64.zip"
