#!/usr/bin/env bash
# Package a separately installable extension suite for a Wixels release.
# Usage: ./package-extension-pack.sh X.Y.Z [Suite]   (Suite defaults to Cynaberii)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"
SUITE="${2:-Cynaberii}"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ./package-extension-pack.sh X.Y.Z [Suite] (numeric semantic version, for example 0.1.0)" >&2
    exit 2
fi

case "$SUITE" in
    Cynaberii) EXPECTED_PLUGINS=12 ;;
    Macos)     EXPECTED_PLUGINS=6 ;;
    *)
        echo "error: unknown suite '$SUITE' (expected Cynaberii or Macos)" >&2
        exit 2
        ;;
esac

cd "$ROOT"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wixels-extension-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
PACK_NAME="Wixels-$SUITE-$VERSION"
PACK_ROOT="$STAGING/$PACK_NAME"
PLUGINS="$PACK_ROOT/plugins"
RELEASE="$ROOT/.build/release"

echo "==> building Wixels $VERSION release host for extension validation"
swift build -c release
WIXELS_WIDGET_SUITE="$SUITE" "$ROOT/build-plugins.sh" release

shopt -s nullglob
widget_dylibs=("$ROOT/build/release/plugins/$SUITE"/libWidget*.dylib)
theme_dylibs=("$ROOT/build/release/plugins/$SUITE"/libTheme*.dylib)
if [ "${#widget_dylibs[@]}" -ne "$EXPECTED_PLUGINS" ] || [ "${#theme_dylibs[@]}" -ne 1 ]; then
    echo "error: expected $EXPECTED_PLUGINS $SUITE widgets and one theme" >&2
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

MANIFEST="$ROOT/build/release/plugins/$SUITE/wixels-package.json"
if [ ! -f "$MANIFEST" ]; then
    echo "error: $SUITE build output is missing wixels-package.json" >&2
    exit 1
fi

mkdir -p "$PLUGINS/$SUITE"
cp "${widget_dylibs[@]}" "$PLUGINS/$SUITE/"
cp "${theme_dylibs[@]}" "$PLUGINS/$SUITE/"
cp "$MANIFEST" "$PLUGINS/$SUITE/wixels-package.json"
cp "$ROOT/LICENSE" "$PACK_ROOT/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$PACK_ROOT/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Vendor/MediaRemoteAdapter/LICENSE" "$PACK_ROOT/MediaRemoteAdapter-LICENSE"
cp "$ROOT/docs/extension-pack-INSTALL.md" "$PACK_ROOT/INSTALL.md"

ZIP="$STAGING/$PACK_NAME-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$PACK_ROOT" "$ZIP"

echo "==> verifying archive round trip"
EXTRACTED="$STAGING/extracted"
mkdir -p "$EXTRACTED"
ditto -x -k "$ZIP" "$EXTRACTED"
EXTRACTED_ROOT="$EXTRACTED/$PACK_NAME"
if [ "$(find "$EXTRACTED_ROOT/plugins" -maxdepth 2 -name 'libWidget*.dylib' | wc -l | tr -d ' ')" -ne "$EXPECTED_PLUGINS" ] ||
   [ "$(find "$EXTRACTED_ROOT/plugins/$SUITE" -maxdepth 1 -name 'libTheme*.dylib' | wc -l | tr -d ' ')" -ne 1 ] ||
   [ ! -f "$EXTRACTED_ROOT/plugins/$SUITE/wixels-package.json" ]; then
    echo "error: archive lost extension payload" >&2
    exit 1
fi
mkdir -p "$STAGING/plugin-test-home/.config/wixels"
mkdir -p "$STAGING/plugin-test-home/.config/wixels/plugins/$SUITE"
cp "$EXTRACTED_ROOT/plugins/$SUITE"/*.dylib "$STAGING/plugin-test-home/.config/wixels/plugins/$SUITE/"
cp "$EXTRACTED_ROOT/plugins/$SUITE/wixels-package.json" "$STAGING/plugin-test-home/.config/wixels/plugins/$SUITE/"
HOME="$STAGING/plugin-test-home" WIXELS_WIDGET_SUITE="$SUITE" "$RELEASE/wixels" --plugin-tests

mkdir -p "$ROOT/dist"
rm -rf "${ROOT:?}/dist/$PACK_NAME"
rm -f "$ROOT/dist/$PACK_NAME-arm64.zip"
mv "$PACK_ROOT" "$ROOT/dist/$PACK_NAME"
mv "$ZIP" "$ROOT/dist/$PACK_NAME-arm64.zip"

echo "==> packaged dist/$PACK_NAME"
echo "==> packaged dist/$PACK_NAME-arm64.zip"
