#!/bin/bash
# Step 1: tag + push to trigger CI (CI builds Ice.zip on the GitHub Release).
# Usage: ./script/release.sh vX.Y.Z   (e.g. ./script/release.sh v0.11.13)
# Next:  wait for CI green, then ./script/update-appcast.sh vX.Y.Z
set -e
cd "$(dirname "$0")/.."

TAG="${1:-}"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 vX.Y.Z   (e.g. $0 v0.11.13)"
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "tag '$TAG' already exists"
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "working tree dirty — commit or stash first"
  exit 1
fi

./script/ci-local.sh "$TAG"

git tag "$TAG"
git push origin "$TAG"
echo "pushed $TAG — watch CI, then run: ./script/update-appcast.sh $TAG"
