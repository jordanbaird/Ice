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

# Whose signature to build with. An Apple developer certificate is worth using when there is one:
# macOS keys Accessibility and Screen Recording to the signature, and a team's is the same from one
# build to the next, while an ad-hoc signature changes with every build and the permissions have to
# be granted again. The team is the certificate's OU, not the name in brackets after it.
# Set DEVELOPMENT_TEAM to choose one yourself; leave it unset to be asked nothing.
TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
fi

# The hardened runtime is off whichever way this goes. With an ad-hoc signature it refuses to load
# Sparkle, which carries a team of its own — "mapping process and mapped file (non-platform) have
# different Team IDs" — while `codesign --verify --deep --strict` passes all the same, so the
# script used to install a bundle that could not launch (jordanbaird/Ice#1006, @Theralley). A copy
# installed from here is run by its builder rather than distributed, so it gives up nothing it needs.
if [ -n "$TEAM" ]; then
    echo "==> Building, signed by team $TEAM"
    SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)
else
    # No certificate on this Mac. The project must not name a team here either, or Xcode stops at
    # "No signing certificate Mac Development found" and never reaches the ad-hoc fallback — which
    # is what a team identifier left in the project did to everyone else (reported by @stickerdaniel
    # on jordanbaird/Ice#995).
    echo "==> Building, signed ad hoc: no Apple developer certificate on this Mac"
    SIGNING=(
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES
        CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
    )
fi

xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    ENABLE_HARDENED_RUNTIME=NO "${SIGNING[@]}" \
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
