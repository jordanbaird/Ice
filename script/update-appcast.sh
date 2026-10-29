#!/bin/bash
# Step 2: fetch Ice.zip from the GitHub Release and publish appcast.xml.
# Without this, installed apps never see the update (SUFeedURL has no new entry).
# Usage: ./script/update-appcast.sh vX.Y.Z [--key <private-key.pem>] [--releases-repo <git-url>]
# Env:   SPARKLE_PRIVATE_KEY=path/to/key.pem (matches SUPublicEDKey in Info.plist, never commit it).
#        Omit --key to use the private key stored in your Keychain instead.
#        DOWNLOAD_URL_PREFIX to override enclosure URLs (default: Ice releases for TAG)
# Needs: gh, generate_appcast (from Sparkle: https://sparkle-project.org/documentation/#publishing-updates)
set -e
cd "$(dirname "$0")/.."

TAG=""; KEY="${SPARKLE_PRIVATE_KEY:-}"; RELEASES_REPO="${ICE_RELEASES_REPO:-https://github.com/cavaldos/ice-releases.git}"
while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY="$2"; shift 2;;
    --releases-repo) RELEASES_REPO="$2"; shift 2;;
    -h|--help) sed -n '2,8p' "$0"; exit 0;;
    v*) TAG="$1"; shift;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 vX.Y.Z [--key <private-key.pem>]"
  exit 1
fi
command -v gh >/dev/null || { echo "missing gh — brew install gh"; exit 1; }
command -v generate_appcast >/dev/null || { echo "missing generate_appcast — download Sparkle tools (see header)"; exit 1; }
[ -z "$KEY" ] || [ -f "$KEY" ] || { echo "private key not found: '$KEY'"; exit 1; }
[ -n "$KEY" ] && KEY_ARG=(-f "$KEY") || KEY_ARG=()
PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/cavaldos/Ice/releases/download/$TAG/}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
CHECKOUT="$WORK/releases"
git clone --depth 1 "$RELEASES_REPO" "$CHECKOUT" >/dev/null \
  || { echo "cannot clone $RELEASES_REPO — create the repo and enable GitHub Pages first"; exit 1; }
# Keep history: generate_appcast preserves entries from the old xml in the same folder.
[ -f "$CHECKOUT/appcast.xml" ] && cp "$CHECKOUT/appcast.xml" "$WORK/appcast.xml"
gh release download "$TAG" -R cavaldos/Ice -p 'Ice.zip' -D "$WORK"

generate_appcast "${KEY_ARG[@]}" --download-url-prefix "$PREFIX" "$WORK"
cp "$WORK/appcast.xml" "$CHECKOUT/appcast.xml"
git -C "$CHECKOUT" add appcast.xml
git -C "$CHECKOUT" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
  commit -m "appcast: $TAG" >/dev/null && git -C "$CHECKOUT" push origin HEAD || echo "(nothing new to push)"

echo "done — verify: https://cavaldos.github.io/ice-releases/appcast.xml contains $TAG"
echo "note: users only auto-update if 'Automatically check for updates' is ON in About"
