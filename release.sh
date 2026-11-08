#!/bin/bash
# Baut die App für alle Macs und packt sie als ZIP zum Hochladen auf GitHub.
# Aufruf: ./release.sh v4.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Bitte Versionsnummer angeben, z. B. ./release.sh v4.0}"
NUMBER="${VERSION#v}"

# Versionsnummer in die App schreiben
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NUMBER}" Info.plist

UNIVERSAL=1 ./build.sh

# Releases immer mit demselben Zertifikat: Sonst verlieren alle nach dem Update ihre Erlaubnisse
if codesign -d -r- build/Pixelcat.app 2>&1 | grep -q "cdhash"; then
  if [ "${ALLOW_ADHOC:-0}" != "1" ]; then
    echo "✗ Die App ist nur ad hoc signiert. Erst ./make-signing-cert.sh ausführen (oder ALLOW_ADHOC=1 setzen)." >&2
    exit 1
  fi
fi

ZIP="build/Pixelcat-${VERSION}.zip"
rm -f "${ZIP}"
ditto -c -k --norsrc --noextattr --keepParent build/Pixelcat.app "${ZIP}"

echo "✓ Release-Datei: ${ZIP}"
lipo -archs build/Pixelcat.app/Contents/MacOS/Pixelcat
