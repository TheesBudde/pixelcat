#!/bin/bash
# Rendert Pixelbilder (Blasen, neue Posen, Requisiten) zur Sichtprüfung nach build/preview/.
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
