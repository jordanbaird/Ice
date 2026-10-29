#!/bin/bash
set -e
# Usage: ./script/run.sh — build Debug and launch locally.
cd "$(dirname "$0")/.."
# Ad-hoc sign: repo pins team K2ATHQPJDP which you don't have cert for
SIGN_ARGS='CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug -destination "platform=macOS,arch=arm64" $SIGN_ARGS build
APP_DIR=$(xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug -destination "platform=macOS,arch=arm64" -showBuildSettings 2>/dev/null | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
pkill -x Ice 2>/dev/null || true
open "$APP_DIR/Ice.app"
