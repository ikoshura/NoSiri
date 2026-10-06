#!/bin/bash
# Builds NoSiri.app into ./build/ with plain swiftc (no Xcode project needed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/NoSiri.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macosx26.0" \
  -framework SwiftUI \
  -o "$APP/Contents/MacOS/NoSiri" \
  "$ROOT/Sources/NoSiri/App.swift"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Bundle the app icon asset so it is reachable via Bundle.main at runtime.
cp "$ROOT/Resources/icon.svg" "$APP/Contents/Resources/icon.svg"

# Build the macOS .icns from Resources/AppIcon.appiconset (source of truth).
# iconutil refuses mixed iOS/mac catalogs, so stage a mac-only copy first.
ICONSET="$ROOT/Resources/AppIcon.appiconset"
if [ -d "$ICONSET" ] && [ -f "$ICONSET/ItunesArtwork@2x.png" ]; then
  rm -f "$APP/Contents/Resources/AppIcon.icns"
  # iconutil requires the catalog directory to end in .iconset
  STAGE="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$STAGE"
  trap 'rm -rf "$(dirname "$STAGE")"' EXIT
  for f in "$ICONSET"/icon_*.png; do cp "$f" "$STAGE/"; done
  /usr/bin/python3 - "$STAGE" <<'PY'
import json, os, sys
stage = sys.argv[1]
icons = sorted(f for f in os.listdir(stage) if f.endswith('.png'))
imgs = []
for f in icons:
    base = os.path.splitext(f)[0]
    size = int(base.split('x')[0].split('_')[-1])
    scale = 2 if base.endswith('@2x') else 1
    imgs.append({"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": f})
json.dump({"images": imgs, "info": {"version": 1, "author": "build.sh"}},
          open(os.path.join(stage, "Contents.json"), "w"), indent=2)
PY
  iconutil -c icns "$STAGE" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$STAGE")"
  trap - EXIT
fi
# Sign for real when a Developer ID certificate is available, since Apple's
# notary service rejects ad-hoc signatures outright. Ad-hoc is kept as a
# fallback so a fresh clone still builds and runs locally.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' | head -1 \
  | sed -E 's/.*"([^"]+)".*/\1/')"

if [ -n "$IDENTITY" ]; then
  # The hardened runtime is mandatory for notarization. The app only ever
  # shells out to /usr/bin/defaults and /usr/bin/killall, so it needs no
  # entitlements beyond the default set.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed: $IDENTITY"
else
  codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
    codesign --force --sign - "$APP"
  echo "Signed: ad-hoc (no Developer ID found; NOT notarizable)"
fi

echo "Built $APP"
echo "Run with: open $APP"

# ---------------------------------------------------------------------------
# Package build/NoSiri.app into dist/NoSiri-<version>.dmg (AppleScript-free, no
# Finder dependency, so it works headlessly in CI as well as locally).
# ---------------------------------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST="$ROOT/dist"
DMG="$DIST/NoSiri-$VERSION.dmg"
rm -f "$DMG"
mkdir -p "$DIST"
TMP="$(mktemp -d)/rw"
mkdir -p "$TMP"
cp -R "$APP" "$TMP/"
ln -s /Applications "$TMP/Applications"
/usr/bin/hdiutil create -volname "NoSiri $VERSION" -srcfolder "$TMP" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$TMP")"
echo "Packaged $DMG"
