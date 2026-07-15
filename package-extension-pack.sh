#!/usr/bin/env bash
# Package the separately installable Cynaberii extensions for a Wixels release.
# Usage: ./package-extension-pack.sh X.Y.Z
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"
SUITE="Cynaberii"

if [ "$#" -ne 1 ] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ./package-extension-pack.sh X.Y.Z (numeric semantic version, for example 0.1.0)" >&2
    exit 2
fi

cd "$ROOT"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wixels-extension-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
PACK_ROOT="$STAGING/Wixels-Cynaberii-$VERSION"
PLUGINS="$PACK_ROOT/plugins"
RELEASE="$ROOT/.build/release"
EXPECTED_PLUGINS=12

echo "==> building Wixels $VERSION release host for extension validation"
swift build -c release
WIXELS_WIDGET_SUITE="$SUITE" "$ROOT/build-plugins.sh" release

shopt -s nullglob
widget_dylibs=("$ROOT/build/release/plugins/$SUITE"/libWidget*.dylib)
theme_dylibs=("$ROOT/build/release/plugins/$SUITE"/libTheme*.dylib)
if [ "${#widget_dylibs[@]}" -ne "$EXPECTED_PLUGINS" ] || [ "${#theme_dylibs[@]}" -ne 1 ]; then
    echo "error: expected $EXPECTED_PLUGINS Cynaberii widgets and one theme" >&2
    exit 1
fi

echo "==> validating extension runtime"
WIXELS_PLUGIN_ROOT="$ROOT/build/release" WIXELS_WIDGET_SUITE="$SUITE" "$RELEASE/wixels" --layout-tests
WIXELS_PLUGIN_ROOT="$ROOT/build/release" WIXELS_WIDGET_SUITE="$SUITE" "$RELEASE/wixels" --plugin-tests

echo "==> validating Apple-silicon extensions"
for binary in "${widget_dylibs[@]}" "${theme_dylibs[@]}"; do
    if [ "$(lipo -archs "$binary")" != "arm64" ]; then
        echo "error: $(basename "$binary") is not arm64-only" >&2
        exit 1
    fi
    if ! vtool -show-build "$binary" | grep -Eq 'minos[[:space:]]+14(\.0+)?$'; then
        echo "error: $(basename "$binary") does not target macOS 14.0" >&2
        exit 1
    fi
    codesign --verify --strict --verbose=2 "$binary"
done

mkdir -p "$PLUGINS/$SUITE"
cp "${widget_dylibs[@]}" "$PLUGINS/$SUITE/"
cp "${theme_dylibs[@]}" "$PLUGINS/$SUITE/"
cp "$ROOT/LICENSE" "$PACK_ROOT/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$PACK_ROOT/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Vendor/MediaRemoteAdapter/LICENSE" "$PACK_ROOT/MediaRemoteAdapter-LICENSE"
cp "$ROOT/docs/extension-pack-INSTALL.md" "$PACK_ROOT/INSTALL.md"

ZIP="$STAGING/Wixels-Cynaberii-$VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$PACK_ROOT" "$ZIP"

echo "==> verifying archive round trip"
EXTRACTED="$STAGING/extracted"
mkdir -p "$EXTRACTED"
ditto -x -k "$ZIP" "$EXTRACTED"
EXTRACTED_ROOT="$EXTRACTED/Wixels-Cynaberii-$VERSION"
if [ "$(find "$EXTRACTED_ROOT/plugins" -maxdepth 2 -name 'libWidget*.dylib' | wc -l | tr -d ' ')" -ne "$EXPECTED_PLUGINS" ] ||
   [ "$(find "$EXTRACTED_ROOT/plugins/$SUITE" -maxdepth 1 -name 'libTheme*.dylib' | wc -l | tr -d ' ')" -ne 1 ]; then
    echo "error: archive lost extension payload" >&2
    exit 1
fi
mkdir -p "$STAGING/plugin-test-home/.config/wixels"
mkdir -p "$STAGING/plugin-test-home/.config/wixels/plugins/$SUITE"
cp "$EXTRACTED_ROOT/plugins/$SUITE"/*.dylib "$STAGING/plugin-test-home/.config/wixels/plugins/$SUITE/"
HOME="$STAGING/plugin-test-home" WIXELS_WIDGET_SUITE="$SUITE" "$RELEASE/wixels" --plugin-tests

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Wixels-Cynaberii-$VERSION"
rm -f "$ROOT/dist/Wixels-Cynaberii-$VERSION-arm64.zip"
mv "$PACK_ROOT" "$ROOT/dist/Wixels-Cynaberii-$VERSION"
mv "$ZIP" "$ROOT/dist/Wixels-Cynaberii-$VERSION-arm64.zip"

echo "==> packaged dist/Wixels-Cynaberii-$VERSION"
echo "==> packaged dist/Wixels-Cynaberii-$VERSION-arm64.zip"
