#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/AtomRGB.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/AtomRGB-$VERSION.dmg"
ICONSET_DIR="$DIST_DIR/AtomRGB.iconset"

if [[ ! -f "$ROOT_DIR/AtomRGB.png" ]]; then
    print -u2 "Missing logo source: $ROOT_DIR/AtomRGB.png"
    exit 1
fi

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$APP_PATH" "$DMG_ROOT" "$ICONSET_DIR" "$DMG_PATH"

print "Building AtomRGB $VERSION..."
swift build -c release --product AtomRGBApp
BIN_DIR="$(swift build -c release --product AtomRGBApp --show-bin-path)"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/AtomRGBApp" "$APP_PATH/Contents/MacOS/AtomRGBApp"
cp "$ROOT_DIR/packaging/Info.plist" "$APP_PATH/Contents/Info.plist"

mkdir -p "$ICONSET_DIR"
for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${spec%% *}"
    name="${spec#* }"
    sips -s format png -z "$size" "$size" "$ROOT_DIR/AtomRGB.png" \
        --out "$ICONSET_DIR/$name" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AtomRGB.icns"

if command -v codesign >/dev/null 2>&1; then
    codesign --deep --force --sign - "$APP_PATH" >/dev/null
fi

mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
    -volname "AtomRGB $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
print "Created $DMG_PATH"
