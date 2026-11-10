#!/bin/bash
#
# Verifies plan 1 on macOS 27: Ice hides the hidden and always-hidden sections soon
# after launch, reveals the hidden section on hover without exposing always-hidden items, and
# every item comes back when Ice quits.
#
# Requirements: Ice installed with Scripts/install.sh, Thaw not running, the
# external display at the origin, and no app menus reaching into REGION.
#
# Usage: Scripts/macos27/verify-conceal.sh [empty-x] [empty-y]
#   (empty-x, empty-y) is an empty spot on the external display's menu bar.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMPTY_X="${1:-900}"
EMPTY_Y="${2:-12}"
REGION="${REGION:-700,0,1220,34}"
IFS=, read -r REGION_X _ REGION_W _ <<< "$REGION"
CYCLES="${CYCLES:-10}"
WORK="$(mktemp -d /tmp/ice-verify-conceal.XXXXXX)"
mkdir -p "$WORK/bin" "$WORK/steady" "$WORK/cycles"

swiftc -O "$ROOT/Scripts/macos27/pointer.swift" -o "$WORK/bin/pointer"
swiftc -O "$ROOT/Scripts/macos27/analyze-frames.swift" -o "$WORK/bin/analyze-frames"

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
quit_ice() {
    osascript -e 'tell application id "com.jordanbaird.Ice" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null || return 0; sleep 0.25; done
}
# The bar draws its items dimmer while it is inactive, which moves the measured edge by a
# few points, so steady captures are taken with the starting application frontmost.
FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
leftmost() {
    osascript -e "tell application \"$FRONT_APP\" to activate" >/dev/null 2>&1 || true
    sleep 0.5
    screencapture -x -R "$REGION" "$WORK/steady/$1.png"
    "$WORK/bin/analyze-frames" "$WORK/steady" "$REGION_X" "$REGION_W" | awk -v name="$1" '$1 == name { print $2 }'
}

# `defaults read` prints 1/0, but `defaults write -bool` only accepts true/false.
as_bool() { case "$1" in 1|true|YES|yes) echo true ;; *) echo false ;; esac; }
ORIGINAL_ICE_BAR=$(as_bool "$(defaults read com.jordanbaird.Ice UseIceBar 2>/dev/null || echo 1)")
ORIGINAL_HOVER=$(as_bool "$(defaults read com.jordanbaird.Ice ShowOnHover 2>/dev/null || echo 1)")
start_ice() {
    open "$HOME/Applications/Ice.app"
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null && return 0; sleep 0.25; done
}
# Leave Ice running, the way the run found it. A run that ended with Ice down left the
# machine concealing nothing, and whatever was looked at next showed nothing worth seeing.
restore() {
    quit_ice
    defaults write com.jordanbaird.Ice UseIceBar -bool "$ORIGINAL_ICE_BAR"
    defaults write com.jordanbaird.Ice ShowOnHover -bool "$ORIGINAL_HOVER"
    start_ice
}
trap restore EXIT

quit_ice
"$WORK/bin/pointer" glide 960 540
ALL_VISIBLE=$(leftmost all-visible)

defaults write com.jordanbaird.Ice UseIceBar -bool false
defaults write com.jordanbaird.Ice ShowOnHover -bool true
open "$HOME/Applications/Ice.app"
sleep 3
EARLY=$(leftmost early)
sleep 7
HIDDEN=$(leftmost hidden)

"$WORK/bin/pointer" glide "$EMPTY_X" "$EMPTY_Y"
"$WORK/bin/pointer" hold 1.5
REVEALED=$(leftmost revealed)
"$WORK/bin/pointer" glide "$EMPTY_X" 540
"$WORK/bin/pointer" hold 2

( while [ ! -f "$WORK/stop" ]; do screencapture -x -R "$REGION" "$WORK/cycles/$(now).png"; done ) &
CAPTURE=$!
for _ in $(seq 1 "$CYCLES"); do
    "$WORK/bin/pointer" glide "$EMPTY_X" "$EMPTY_Y"
    "$WORK/bin/pointer" hold 1.2
    "$WORK/bin/pointer" glide "$EMPTY_X" 540
    "$WORK/bin/pointer" hold 1.5
done
touch "$WORK/stop"
wait "$CAPTURE"
LOWEST=$("$WORK/bin/analyze-frames" "$WORK/cycles" "$REGION_X" "$REGION_W" | awk '$2 >= 0 { print $2 }' | sort -n | head -1)
FRAMES=$(ls "$WORK/cycles" | wc -l | tr -d ' ')

quit_ice
sleep 2
AFTER_QUIT=$(leftmost after-quit)

echo "all-visible=$ALL_VISIBLE early=$EARLY hidden=$HIDDEN revealed=$REVEALED lowest-during-cycles=$LOWEST frames=$FRAMES after-quit=$AFTER_QUIT"
FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "items are hidden within 3 s of launch" "[ $EARLY -gt $((ALL_VISIBLE + 20)) ]"
check "items are hidden" "[ $HIDDEN -gt $((ALL_VISIBLE + 20)) ]"
check "hover reveals the hidden section" "[ $REVEALED -lt $((HIDDEN - 20)) ]"
check "always-hidden items stay hidden while revealed" "[ $REVEALED -gt $((ALL_VISIBLE + 20)) ]"
# The reveal animation overshoots its resting place by up to 4 pt (measured). An
# always-hidden item that flashes moves the edge by a whole item, at least 24 pt.
check "always-hidden items never flash in $CYCLES cycles" "[ $LOWEST -ge $((REVEALED - 10)) ]"
check "every item returns when Ice quits" "[ $AFTER_QUIT -ge $((ALL_VISIBLE - 3)) ] && [ $AFTER_QUIT -le $((ALL_VISIBLE + 3)) ]"
echo "frames: $WORK"
exit $FAILED
