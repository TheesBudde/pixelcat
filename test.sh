#!/bin/bash
# Spielt die Katzenkorb-Szenarien durch (Tests/main.swift) – braucht nur die Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 $(ls Sources/*.swift | grep -v main.swift) Tests/main.swift -o build/basket-tests 2>&1 \
  | grep -v "warning" || true
build/basket-tests
