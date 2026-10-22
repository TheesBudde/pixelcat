#!/bin/bash
# Rendert Pixelbilder (Blasen, Posen, Requisiten) und das Einstellungsfenster zur Sichtprüfung nach build/preview/.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/preview
# Bei einem Compilerfehler abbrechen, statt eine alte Version laufen zu lassen
rm -f build/preview-bin
if ! swiftc -swift-version 5 $(ls Sources/*.swift | grep -v main.swift) Tests/Preview/main.swift -o build/preview-bin 2> build/compile.log; then
  grep -E "error" build/compile.log || cat build/compile.log
  exit 1
fi
build/preview-bin build/preview
# Dazu das Einstellungsfenster als Bild (ganze Seite)
if swiftc -swift-version 5 $(ls Sources/*.swift | grep -v main.swift) Tests/SettingsShot/main.swift -o build/settings-shot 2> build/compile.log; then
  build/settings-shot build/preview/einstellungen.png > /dev/null
else
  grep -E "error" build/compile.log || cat build/compile.log
  exit 1
fi
