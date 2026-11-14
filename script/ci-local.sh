#!/bin/bash
# Mirror of .github/workflows/lint.yml + release.yml — run before push/tag.
# Usage: ./script/ci-local.sh [vX.Y.Z]  (pass tag to also validate tag format)
set -e
cd "$(dirname "$0")/.."

if ! command -v swiftlint >/dev/null; then
  echo "swiftlint not found — run: brew install swiftlint"
  exit 1
fi
# Keep in sync with .github/workflows/lint.yml (SWIFTLINT_VERSION).
if [ "$(swiftlint version)" != "0.65.1" ]; then
  echo "warning: local swiftlint $(swiftlint version) != CI 0.65.1 — run: brew upgrade swiftlint"
fi
echo "==> swiftlint --strict"
swiftlint --strict

echo "==> xcodebuild -version (CI builds with Xcode 26.6 on macos-26)"
xcodebuild -version
XCODE_MAJOR=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
if [ "${XCODE_MAJOR:-0}" -lt 26 ]; then
  echo "warning: Xcode $XCODE_MAJOR < 26 links the legacy appearance; CI uses Xcode 26.6 (Liquid Glass SDK)"
fi

echo "==> xcodebuild Release (same flags as release.yml)"
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  clean build >/dev/null
echo "build OK"

if [ -n "$1" ]; then
  if ! [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "tag '$1' must look like vX.Y.Z (e.g. v0.11.13)"
    exit 1
  fi
  echo "tag OK: $1"
fi

echo "ci-local PASS"
