#!/bin/bash
# Baut build/Pixelkatze.app – braucht nur die Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Pixelkatze.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Kompiliere …"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  Sources/*.swift -o "$APP/Contents/MacOS/Pixelkatze"

cp Info.plist "$APP/Contents/Info.plist"

echo "→ Erzeuge App-Symbol …"
"$APP/Contents/MacOS/Pixelkatze" --export-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signiere (ad hoc) …"
codesign --force --sign - "$APP" >/dev/null

echo "✓ Fertig: $APP"
