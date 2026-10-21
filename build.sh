#!/bin/bash
# Baut build/Pixelkatze.app – braucht nur die Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Pixelkatze.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Kompiliere …"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  # Für Apple Silicon und Intel – damit die App auf jedem Mac läuft
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
      Sources/*.swift -o "build/Pixelkatze-$arch"
  done
  lipo -create build/Pixelkatze-arm64 build/Pixelkatze-x86_64 -output "$APP/Contents/MacOS/Pixelkatze"
  rm build/Pixelkatze-arm64 build/Pixelkatze-x86_64
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    Sources/*.swift -o "$APP/Contents/MacOS/Pixelkatze"
fi

cp Info.plist "$APP/Contents/Info.plist"

echo "→ Erzeuge App-Symbol …"
"$APP/Contents/MacOS/Pixelkatze" --export-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signiere (ad hoc) …"
codesign --force --sign - "$APP" >/dev/null

echo "✓ Fertig: $APP"
