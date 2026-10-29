#!/bin/bash
set -e
# Usage: ./script/dev.sh [vX.Y.Z] — dev-only: kills the old build, builds Debug,
# runs from a fixed path so Accessibility / Screen Recording is granted only once.
# Pass a version to check for duplicates: ./script/dev.sh v0.11.12
cd "$(dirname "$0")/.."

VERSION_ARGS=()
if [ $# -ge 1 ]; then
    VERSION="${1#v}"
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Version '$1' must look like vX.Y.Z (e.g. ./script/dev.sh v0.11.12)"
        exit 1
    fi
    # Same as build.sh: 1117 + commit count so the build number keeps increasing.
    BUILD_NUMBER=$((1117 + $(git rev-list --count HEAD)))
    echo "→ Version override: $VERSION ($BUILD_NUMBER)"
    VERSION_ARGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
elif [ -n "${MARKETING_VERSION:-}" ] || [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
    [ -n "${MARKETING_VERSION:-}" ] && VERSION_ARGS+=(MARKETING_VERSION="$MARKETING_VERSION")
    [ -n "${CURRENT_PROJECT_VERSION:-}" ] && VERSION_ARGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION")
fi

IDENTITY="${ICE_CODE_SIGN_IDENTITY:-Ice Dev}"
DEV_APP="${ICE_DEV_APP:-/Applications/Ice-Dev.app}"
DEST="platform=macOS,arch=arm64"

SIGN_ARGS=()
if [ "$IDENTITY" = "-" ]; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
elif security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" "DEVELOPMENT_TEAM=${ICE_DEVELOPMENT_TEAM:-}")
else
    echo "⚠️  No \"$IDENTITY\" cert found — falling back to an ad-hoc build (macOS will ask for permissions again)."
    echo "   One-time setup: Keychain Access > Certificate Assistant > Create a Certificate…"
    echo "   Name: $IDENTITY | Identity Type: Self Signed Root | Certificate Type: Code Signing"
    echo "   Then re-run this script, or force ad-hoc: ICE_CODE_SIGN_IDENTITY=- ./script/dev.sh"
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

echo "→ Building Debug (sign: ${IDENTITY})…"
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
    -destination "$DEST" "${SIGN_ARGS[@]}" "${VERSION_ARGS[@]}" build

APP_DIR=$(xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
    -destination "$DEST" "${VERSION_ARGS[@]}" -showBuildSettings 2>/dev/null | sed -n 's/^ *BUILT_PRODUCTS_DIR *= *//p' | head -1)
SRC_APP="$APP_DIR/Ice.app"
[ -d "$SRC_APP" ] || { echo "❌ Not found: $SRC_APP"; exit 1; }

echo "→ Killing old build…"
pkill -x Ice 2>/dev/null || true
sleep 1

echo "→ Copying to $DEV_APP (fixed path = keeps permissions)…"
rm -rf "$DEV_APP"
ditto "$SRC_APP" "$DEV_APP"
echo "→ Re-signing uniformly ($IDENTITY, fixes dyld Team IDs)…"
codesign --force --deep --sign "$IDENTITY" "$DEV_APP"
codesign --verify --deep --strict "$DEV_APP"
echo "→ Current signature:"
codesign -dvvv "$DEV_APP" 2>&1 | grep -E "^(Authority|Identifier)" || true

BUILT_VERSION=$(defaults read "$DEV_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
BUILT_BUILD=$(defaults read "$DEV_APP/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")
echo "→ Built version: $BUILT_VERSION ($BUILT_BUILD)"

echo "→ Opening new build…"
open "$DEV_APP"
sleep 2
if ICE_PID=$(pgrep -x Ice); then
    echo "✅ App is running (PID $ICE_PID). Ice is a menu-bar app: look for its menu bar icon, it has no Dock icon."
    echo "   Live logs: log stream --predicate 'process == \"Ice\"' --level debug"
else
    echo "❌ App launched then quit — newest crash log: ls -t ~/Library/Logs/DiagnosticReports/Ice-*.ips | head -1"
    exit 1
fi

echo ""
echo "✅ Done. Grant once in System Settings — future runs of this script keep the grant:"
echo "   • Accessibility: open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\""
echo "   • Screen Recording: open \"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture\""
