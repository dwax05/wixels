#!/usr/bin/env bash
# Package a separately installable manifest-backed extension package.
# Usage: ./package-extension-pack.sh X.Y.Z Package
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"
PACKAGE="${2:-}"

if [ "$#" -ne 2 ] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ -z "$PACKAGE" ]; then
    echo "usage: ./package-extension-pack.sh X.Y.Z Package (numeric semantic version, for example 0.1.0)" >&2
    exit 2
fi

MANIFEST="$ROOT/plugins/$PACKAGE/wixels-package.json"
[ -f "$MANIFEST" ] || { echo "error: package '$PACKAGE' is missing plugins/$PACKAGE/wixels-package.json" >&2; exit 2; }
EXPECTED_PLUGINS="$( { rg -o '"kind"[[:space:]]*:' "$MANIFEST" || true; } | wc -l | tr -d ' ')"
EXPECTED_THEMES="$( { rg -o '"themeID"[[:space:]]*:' "$MANIFEST" || true; } | wc -l | tr -d ' ')"
[ "$((EXPECTED_PLUGINS + EXPECTED_THEMES))" -gt 0 ] || { echo "error: manifest declares no libraries" >&2; exit 2; }
MANIFEST_FILES=()
while IFS= read -r file; do MANIFEST_FILES+=("$file"); done < <(
    rg -o '"file"[[:space:]]*:[[:space:]]*"[^"]+"' "$MANIFEST" | sed -E 's/.*"([^"]+)"$/\1/'
)

declares_file() {
    local wanted="$1" file
    for file in "${MANIFEST_FILES[@]}"; do [ "$file" = "$wanted" ] && return 0; done
    return 1
}

cd "$ROOT"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wixels-extension-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
PACK_NAME="Wixels-$PACKAGE-$VERSION"
PACK_ROOT="$STAGING/$PACK_NAME"
PLUGINS="$PACK_ROOT/plugins"
RELEASE="$ROOT/.build/release"

echo "==> building Wixels $VERSION release host for extension validation"
swift build -c release
WIXELS_WIDGET_SUITE="$PACKAGE" "$ROOT/build-plugins.sh" release

shopt -s nullglob
widget_dylibs=("$ROOT/build/release/plugins/$PACKAGE"/libWidget*.dylib)
theme_dylibs=("$ROOT/build/release/plugins/$PACKAGE"/libTheme*.dylib)
if [ "${#widget_dylibs[@]}" -ne "$EXPECTED_PLUGINS" ] || [ "${#theme_dylibs[@]}" -ne "$EXPECTED_THEMES" ]; then
    echo "error: staged payload does not match $PACKAGE/wixels-package.json" >&2
    exit 1
fi
for file in "${MANIFEST_FILES[@]}"; do
    [ -f "$ROOT/build/release/plugins/$PACKAGE/$file" ] || {
        echo "error: manifest declares missing artifact '$file'" >&2; exit 1
    }
done
for dylib in "${widget_dylibs[@]}" "${theme_dylibs[@]}"; do
    declares_file "$(basename "$dylib")" || {
        echo "error: staged artifact '$(basename "$dylib")' is absent from the manifest" >&2; exit 1
    }
done

echo "==> validating extension runtime"
if [ "$EXPECTED_PLUGINS" -gt 0 ] && [ "$EXPECTED_THEMES" -gt 0 ]; then
    WIXELS_PLUGIN_ROOT="$ROOT/build/release" WIXELS_WIDGET_SUITE="$PACKAGE" "$RELEASE/wixels" --layout-tests
fi
WIXELS_PLUGIN_ROOT="$ROOT/build/release" WIXELS_WIDGET_SUITE="$PACKAGE" "$RELEASE/wixels" --plugin-tests

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

STAGED_MANIFEST="$ROOT/build/release/plugins/$PACKAGE/wixels-package.json"
if [ ! -f "$STAGED_MANIFEST" ]; then
    echo "error: $PACKAGE build output is missing wixels-package.json" >&2
    exit 1
fi

mkdir -p "$PLUGINS/$PACKAGE"
[ "$EXPECTED_PLUGINS" -eq 0 ] || cp "${widget_dylibs[@]}" "$PLUGINS/$PACKAGE/"
[ "$EXPECTED_THEMES" -eq 0 ] || cp "${theme_dylibs[@]}" "$PLUGINS/$PACKAGE/"
cp "$STAGED_MANIFEST" "$PLUGINS/$PACKAGE/wixels-package.json"
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
   [ "$(find "$EXTRACTED_ROOT/plugins/$PACKAGE" -maxdepth 1 -name 'libTheme*.dylib' | wc -l | tr -d ' ')" -ne "$EXPECTED_THEMES" ] ||
   [ ! -f "$EXTRACTED_ROOT/plugins/$PACKAGE/wixels-package.json" ]; then
    echo "error: archive lost extension payload" >&2
    exit 1
fi
mkdir -p "$STAGING/plugin-test-home/.config/wixels"
mkdir -p "$STAGING/plugin-test-home/.config/wixels/plugins/$PACKAGE"
cp "$EXTRACTED_ROOT/plugins/$PACKAGE"/*.dylib "$STAGING/plugin-test-home/.config/wixels/plugins/$PACKAGE/"
cp "$EXTRACTED_ROOT/plugins/$PACKAGE/wixels-package.json" "$STAGING/plugin-test-home/.config/wixels/plugins/$PACKAGE/"
HOME="$STAGING/plugin-test-home" WIXELS_WIDGET_SUITE="$PACKAGE" "$RELEASE/wixels" --plugin-tests

mkdir -p "$ROOT/dist"
rm -rf "${ROOT:?}/dist/$PACK_NAME"
rm -f "$ROOT/dist/$PACK_NAME-arm64.zip"
mv "$PACK_ROOT" "$ROOT/dist/$PACK_NAME"
mv "$ZIP" "$ROOT/dist/$PACK_NAME-arm64.zip"

echo "==> packaged dist/$PACK_NAME"
echo "==> packaged dist/$PACK_NAME-arm64.zip"
