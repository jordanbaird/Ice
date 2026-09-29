#!/bin/bash
#
# Builds Ice and installs it, signed.
#
# Replaces the project's "Copy to Applications" build phase, which cannot work:
# Xcode signs a target *after* its script phases run, so that phase always copies
# an unsigned bundle. macOS then refuses to launch it — "Launchd job spawn
# failed" — and the freshly built app appears simply broken.
#
# Installs to ~/Applications by default, which needs no administrator rights.
# Set DEST=/Applications to install system-wide; that path needs a password.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-$HOME/Applications}"
DERIVED="${DERIVED:-/tmp/ice-build}"

echo "==> Building"
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    | tail -3

APP="$DERIVED/Build/Products/Release/Ice.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

echo "==> Verifying the signature before installing"
# The whole point: never install something that will not launch.
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=' | sed 's/^/    /'

echo "==> Installing to $DEST"
if pgrep -x Ice >/dev/null 2>&1; then
    osascript -e 'quit app "Ice"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x Ice >/dev/null 2>&1 || break
        sleep 0.3
    done
    pgrep -x Ice >/dev/null 2>&1 && pkill -x Ice || true
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/Ice.app"
# ditto, not cp: it preserves the code signature.
ditto "$APP" "$DEST/Ice.app"

echo "==> Verifying the installed copy"
codesign --verify --deep --strict "$DEST/Ice.app"

open -a "$DEST/Ice.app"
echo "==> Running from $DEST/Ice.app"
