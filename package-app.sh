#!/usr/bin/env bash
# Build and package an Apple-silicon Wixels.app for personal distribution.
# Usage: ./package-app.sh X.Y.Z
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
PLIST="$APP/Contents/Info.plist"
RELEASE="$ROOT/.build/release"

echo "==> building Wixels $VERSION"
"$ROOT/build-plugins.sh" release

echo "==> running release test suites"
"$RELEASE/wixels" --config-tests
"$RELEASE/wixels" --layout-tests
"$RELEASE/wixels" --plugin-tests

widget_dylibs=("$RELEASE"/libWidget*.dylib)
theme_dylibs=("$RELEASE"/libTheme*.dylib)
if [ ! -e "${widget_dylibs[0]}" ] || [ "${#widget_dylibs[@]}" -ne 12 ]; then
    echo "error: expected 12 widget dylibs in $RELEASE" >&2
    exit 1
fi
if [ ! -e "${theme_dylibs[0]}" ] || [ "${#theme_dylibs[@]}" -ne 2 ]; then
    echo "error: expected 2 theme dylibs in $RELEASE" >&2
    exit 1
fi

mkdir -p "$MACOS"
cp "$ROOT/packaging/Info.plist" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -lint "$PLIST"

cp "$RELEASE/wixels" "$RELEASE/libWixelsKit.dylib" "$MACOS/"
cp "${widget_dylibs[@]}" "${theme_dylibs[@]}" "$MACOS/"

echo "==> validating Apple-silicon payload"
for binary in "$MACOS/wixels" "$MACOS"/*.dylib; do
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
                dependency_name="$(basename "$dependency")"
                if [ ! -e "$MACOS/$dependency_name" ]; then
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
for dylib in "$MACOS"/*.dylib; do
    codesign --force --sign - "$dylib"
done
codesign --force --sign - "$MACOS/wixels"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> testing packaged plugins"
"$MACOS/wixels" --plugin-tests

ZIP="$STAGING/Wixels-$VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> verifying archive round trip"
EXTRACTED="$STAGING/extracted"
mkdir -p "$EXTRACTED"
ditto -x -k "$ZIP" "$EXTRACTED"
codesign --verify --deep --strict --verbose=2 "$EXTRACTED/Wixels.app"
"$EXTRACTED/Wixels.app/Contents/MacOS/wixels" --plugin-tests

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Wixels.app"
rm -f "$ROOT/dist/Wixels-$VERSION-arm64.zip"
mv "$APP" "$ROOT/dist/Wixels.app"
mv "$ZIP" "$ROOT/dist/Wixels-$VERSION-arm64.zip"

echo "==> packaged dist/Wixels.app"
echo "==> packaged dist/Wixels-$VERSION-arm64.zip"
