#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/ice-notch-overflow-module-cache"
BINARY="${TMPDIR:-/tmp}/ice-notch-overflow-tests"

mkdir -p "$MODULE_CACHE"
xcrun swiftc \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT/Ice/MenuBar/IceBar/NotchOverflowResolver.swift" \
    "$ROOT/scripts/test-notch-overflow.swift" \
    -o "$BINARY"
"$BINARY"
