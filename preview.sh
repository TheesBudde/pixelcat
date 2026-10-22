#!/bin/bash
# Rendert Pixelbilder (Blasen, neue Posen, Requisiten) zur Sichtprüfung nach build/preview/.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/preview
swiftc -swift-version 5 $(ls Sources/*.swift | grep -v main.swift) Tests/Preview/main.swift -o build/preview-bin 2>&1 \
  | grep -v "warning" || true
build/preview-bin build/preview
