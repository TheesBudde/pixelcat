#!/bin/bash
# Erzeugt den Instagram-Clip (9:16, 30 s, mit eigener Chiptune-Musik) nach marketing/pixelcat-instagram.mp4.
# Braucht die Screenshots aus ./preview.sh. Muss im normalen Terminal laufen (der Video-Encoder von macOS).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/promo marketing
./preview.sh > /dev/null
python3 Tests/Promo/music.py build/promo/music.wav Resources/Sounds
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path build/ModuleCache \
  $(ls Sources/*.swift | grep -v main.swift) Tests/Promo/main.swift -o build/promo-bin 2> build/compile.log \
  || { grep -E " error:" build/compile.log; exit 1; }
build/promo-bin build/promo/video.mov build/preview build/promo/music.wav marketing/pixelcat-instagram.mp4
