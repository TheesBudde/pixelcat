#!/bin/bash
# Baut die App für alle Macs und packt sie als ZIP zum Hochladen auf GitHub.
# Aufruf: ./release.sh v4.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Bitte Versionsnummer angeben, z. B. ./release.sh v4.0}"
NUMBER="${VERSION#v}"

# Versionsnummer in die App schreiben
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NUMBER" Info.plist

UNIVERSAL=1 ./build.sh

ZIP="build/Pixelkatze-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Pixelkatze.app "$ZIP"

echo "✓ Release-Datei: $ZIP"
lipo -archs build/Pixelkatze.app/Contents/MacOS/Pixelkatze
