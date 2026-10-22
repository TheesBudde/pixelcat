#!/bin/bash
# Trägt eine auf GitHub veröffentlichte Version in den Homebrew-Tap ein (../homebrew-pixelcat).
# Aufruf: ./update-cask.sh v6.0.1   – erst nachdem die ZIP im Release hochgeladen ist
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Bitte Versionsnummer angeben, z. B. ./update-cask.sh v6.0.1}"
NUMBER="${VERSION#v}"
TAP="${TAP:-../homebrew-pixelcat}"
CASK="$TAP/Casks/pixelcat.rb"
URL="https://github.com/TheesBudde/pixelcat/releases/download/$VERSION/Pixelcat-$VERSION.zip"

# Prüfsumme der tatsächlich veröffentlichten Datei
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/Pixelcat.zip" "$URL"
SHA=$(shasum -a 256 "$TMP/Pixelcat.zip" | cut -d' ' -f1)
rm -rf "$TMP"

sed -i '' -E "s/^  version \".*\"/  version \"$NUMBER\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP" commit -qam "Pixelcat $NUMBER"
git -C "$TAP" push -q
echo "✓ Homebrew-Cask auf $NUMBER ($SHA)"
