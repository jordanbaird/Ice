#!/bin/bash
# Step 2: fetch Ice.zip from the GitHub Release and publish ice/appcast.xml in cavaldos/macos-app-releases.
# Without this, installed apps never see the update (SUFeedURL has no new entry).
# Usage: ./script/update-appcast.sh vX.Y.Z [--key <private-key.pem>]
# Env:   SPARKLE_PRIVATE_KEY=path/to/key.pem (matches SUPublicEDKey in Info.plist, never commit it).
#        Omit --key to use the private key stored in your Keychain instead.
#        RELEASES_SSH / LEGACY_RELEASES_SSH: ssh commands with a deploy key (CI); unset = HTTPS with your own login.
# Needs: gh, generate_appcast (from Sparkle: https://sparkle-project.org/documentation/#publishing-updates)
set -e
cd "$(dirname "$0")/.."

RELEASES_REPO="cavaldos/macos-app-releases"
APPCAST="ice/appcast.xml"
FEED_URL="https://cavaldos.github.io/macos-app-releases/$APPCAST"
# Ice v0.11.35 and older still read their feed from cavaldos/ice-releases, so mirror the appcast
# there until most users have updated. Set to "" before deleting that repo.
LEGACY_REPO="cavaldos/ice-releases"

TAG=""; KEY="${SPARKLE_PRIVATE_KEY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY="$2"; shift 2;;
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
# --ed-key-file, not -f: -f is for legacy DSA keys and rejects the EdDSA key.
[ -n "$KEY" ] && KEY_ARG=(--ed-key-file "$KEY") || KEY_ARG=()
PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/cavaldos/Ice/releases/download/$TAG/}"
GIT_NAME="$(git config user.name || echo github-actions[bot])"
GIT_EMAIL="$(git config user.email || echo github-actions[bot]@users.noreply.github.com)"

# clone <owner/name> <dir> [ssh command]: SSH with a deploy key (CI), else HTTPS.
clone() {
  if [ -n "$3" ]; then
    GIT_SSH_COMMAND="$3" git clone --quiet --depth 1 "git@github.com:$1.git" "$2"
    git -C "$2" config core.sshCommand "$3"
  else
    git clone --quiet --depth 1 "https://github.com/$1.git" "$2"
  fi || { echo "cannot clone $1"; exit 1; }
}

# publish <dir> <file>: commit and push, retrying transient errors (other apps push to the
# same repo). A failed push must fail the script, otherwise CI goes green without publishing.
publish() {
  git -C "$1" add "$2"
  if git -C "$1" diff --cached --quiet; then
    echo "(nothing new to push in $1)"
    return
  fi
  git -C "$1" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" commit -m "appcast: Ice $TAG" >/dev/null
  for attempt in 1 2 3 4 5; do
    git -C "$1" push origin HEAD && return
    [ "$attempt" -eq 5 ] && { echo "push from $1 failed"; exit 1; }
    echo "push failed (attempt $attempt), retrying in $((attempt * 10))s..."
    sleep $((attempt * 10))
    git -C "$1" pull --rebase
  done
}

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/archives"
clone "$RELEASES_REPO" "$WORK/releases" "${RELEASES_SSH:-}"
# Keep history: generate_appcast preserves entries from the old xml in the same folder.
[ -f "$WORK/releases/$APPCAST" ] && cp "$WORK/releases/$APPCAST" "$WORK/archives/appcast.xml"
gh release download "$TAG" -R cavaldos/Ice -p 'Ice.zip' -D "$WORK/archives"

generate_appcast "${KEY_ARG[@]}" --download-url-prefix "$PREFIX" "$WORK/archives"
mkdir -p "$(dirname "$WORK/releases/$APPCAST")"
cp "$WORK/archives/appcast.xml" "$WORK/releases/$APPCAST"
publish "$WORK/releases" "$APPCAST"

if [ -n "$LEGACY_REPO" ]; then
  clone "$LEGACY_REPO" "$WORK/legacy" "${LEGACY_RELEASES_SSH:-}"
  cp "$WORK/archives/appcast.xml" "$WORK/legacy/appcast.xml"
  publish "$WORK/legacy" appcast.xml
fi

echo "done — verify: $FEED_URL contains $TAG"
echo "note: users only auto-update if 'Automatically check for updates' is ON in About"
