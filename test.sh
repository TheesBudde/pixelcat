#!/bin/bash
# Spielt die Katzenkorb-Szenarien durch (Tests/main.swift) – braucht nur die Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# Bei einem Compilerfehler abbrechen, statt eine alte Version laufen zu lassen
rm -f build/basket-tests
if ! swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path build/ModuleCache $(ls Sources/*.swift | grep -v main.swift) Tests/main.swift -o build/basket-tests 2> build/compile.log; then
  grep -E "error" build/compile.log || cat build/compile.log
  exit 1
fi
build/basket-tests
