#!/bin/zsh
# Compila o Trincano (Release por padrão) e assina com a identidade local ou o override.
# Uso: scripts/build.sh [Release|Debug]      Saída: build/Build/Products/<config>/Trincano.app
set -euo pipefail
cd "${0:A:h}/.."
source scripts/signing.sh
CONFIG="${1:-Release}"
resolve_signing
echo "Assinando com: $SIGN_IDENTITY"
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration "$CONFIG" \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="" \
  "${SIGN_FLAGS[@]}" build
APP="build/Build/Products/$CONFIG/Trincano.app"
codesign --verify --deep --strict "$APP"
echo "OK: $APP"
codesign -d -r- "$APP" 2>&1 | grep designated
