#!/bin/bash
# Baut build/Pixelcat.app – braucht nur die Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Pixelcat.app"
rm -rf "${APP}" build/AppIcon.iconset
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

echo "→ Kompiliere …"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  # Für Apple Silicon und Intel – damit die App auf jedem Mac läuft
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "${arch}-apple-macos13.0" -module-cache-path build/ModuleCache \
      Sources/*.swift -o "build/Pixelcat-${arch}"
  done
  lipo -create build/Pixelcat-arm64 build/Pixelcat-x86_64 -output "${APP}/Contents/MacOS/Pixelcat"
  rm build/Pixelcat-arm64 build/Pixelcat-x86_64
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path build/ModuleCache \
    Sources/*.swift -o "${APP}/Contents/MacOS/Pixelcat"
fi

cp Info.plist "${APP}/Contents/Info.plist"
cp Resources/Sounds/*.wav "${APP}/Contents/Resources/"

echo "→ Erzeuge App-Symbol …"
"${APP}/Contents/MacOS/Pixelcat" --export-icon build/AppIcon.iconset
if ! iconutil -c icns build/AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  # iconutil braucht Systemdienste, die in einer Sandbox fehlen – dann die .icns selbst zusammensetzen
  python3 - build/AppIcon.iconset "${APP}/Contents/Resources/AppIcon.icns" <<'PY'
import os, struct, sys
source, target = sys.argv[1], sys.argv[2]
types = [("icp4", "16x16"), ("icp5", "32x32"), ("ic11", "16x16@2x"), ("ic12", "32x32@2x"), ("ic07", "128x128"),
         ("ic13", "128x128@2x"), ("ic08", "256x256"), ("ic14", "256x256@2x"), ("ic09", "512x512"), ("ic10", "512x512@2x")]
chunks = b""
for kind, size in types:
    data = open(os.path.join(source, f"icon_{size}.png"), "rb").read()
    chunks += kind.encode() + struct.pack(">I", len(data) + 8) + data
open(target, "wb").write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
PY
fi

# Mit dem eigenen Zertifikat (./make-signing-cert.sh) erkennt macOS die App nach jedem Update wieder – die Erlaubnisse
# bleiben. Ohne Zertifikat ad hoc: Dann fragt macOS nach jedem Build neu.
IDENTITY="${PIXELCAT_SIGN_IDENTITY:-Pixelcat Signing}"
KEYCHAIN_ARGS=()
if [ -n "${PIXELCAT_KEYCHAIN:-}" ]; then KEYCHAIN_ARGS=(--keychain "${PIXELCAT_KEYCHAIN}"); fi
if security find-identity -p codesigning ${PIXELCAT_KEYCHAIN:+"${PIXELCAT_KEYCHAIN}"} 2>/dev/null | grep -q "\"${IDENTITY}\""; then
  echo "→ Signiere mit „${IDENTITY}“ …"
  codesign --force --sign "${IDENTITY}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "${APP}" >/dev/null
else
  echo "→ Signiere (ad hoc) …"
  echo "  Tipp: ./make-signing-cert.sh einmal ausführen, dann bleiben die Erlaubnisse nach Updates erhalten."
  codesign --force --sign - "${APP}" >/dev/null
fi

echo "✓ Fertig: ${APP}"
