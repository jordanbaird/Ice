#!/bin/zsh
# Verificação local (o CI do GitHub está sem minutos): lint + testes + build Release.
set -euo pipefail
cd "${0:A:h}/.."
swiftlint lint --strict
xcodebuild -project Ice.xcodeproj -scheme TrincanoTests -destination 'platform=macOS' \
  -derivedDataPath build test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO
scripts/build.sh Release
scripts/extract-strings.py check
