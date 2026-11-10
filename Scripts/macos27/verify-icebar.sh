#!/bin/bash
#
# Verifies the Ice Bar on macOS 27: hovering an empty spot of a menu bar opens the Ice
# Bar on that display only, with an image of every hidden application's items, without
# taking the front from the active application; moving away closes it.
#
# Requirements: Ice installed with Scripts/install.sh, EXT_APP with a window on the
# external display, MacOS27Layout set. Leave the mouse and keyboard alone.
#
# Usage: Scripts/macos27/verify-icebar.sh <ext-empty-x> <ext-empty-y> <builtin-empty-x> <builtin-empty-y>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_X="$1"; EXT_Y="$2"; BUILTIN_X="$3"; BUILTIN_Y="$4"
EXT_APP="${EXT_APP:-Safari}"
WORK="$(mktemp -d /tmp/ice-verify-icebar.XXXXXX)"
mkdir -p "$WORK/bin"
swiftc -O "$ROOT/Scripts/macos27/pointer.swift" -o "$WORK/bin/pointer"
swiftc -O "$ROOT/Scripts/macos27/icebar-ax.swift" -o "$WORK/bin/icebar-ax"
swiftc -O "$ROOT/Scripts/macos27/ax-items.swift" -o "$WORK/bin/ax-items"

quit_ice() {
    osascript -e 'tell application id "com.jordanbaird.Ice" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null || return 0; sleep 0.25; done
}
front_app() {
    osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
}
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
defaults write com.jordanbaird.Ice UseIceBar -bool true
defaults write com.jordanbaird.Ice ShowOnHover -bool true
open "$HOME/Applications/Ice.app"
sleep 10
osascript -e "tell application \"$EXT_APP\" to activate" >/dev/null
sleep 2.5

# Hidden-section applications that are running and own menu bar items.
EXPECTED=$(comm -12 \
    <(defaults read com.jordanbaird.Ice MacOS27Layout | sed -nE 's/^ *"?([^" ]+)"? = 1;/\1/p' | sort -u) \
    <("$WORK/bin/ax-items" | awk '{print $4}' | sort -u) | wc -l | tr -d ' ')

open_and_read() {
    local name="$1" x="$2" y="$3" away_y="$4"
    "$WORK/bin/pointer" glide "$x" "$away_y"; "$WORK/bin/pointer" hold 1
    "$WORK/bin/pointer" glide "$x" "$y"; "$WORK/bin/pointer" hold 2.5
    "$WORK/bin/icebar-ax" > "$WORK/$name.txt"
    front_app > "$WORK/$name-front.txt"
    "$WORK/bin/pointer" glide "$x" "$away_y"; "$WORK/bin/pointer" hold 2
    "$WORK/bin/icebar-ax" > "$WORK/$name-after.txt"
}
open_and_read ext "$EXT_X" "$EXT_Y" 540
open_and_read builtin "$BUILTIN_X" "$BUILTIN_Y" 589

panel_x() { awk '/^frame/ { print $2; exit }' "$WORK/$1.txt"; }
item_count() { grep -c '^item ' "$WORK/$1.txt" || true; }
EXT_PANEL_X=$(panel_x ext); BUILTIN_PANEL_X=$(panel_x builtin)
EXT_ITEMS=$(item_count ext); BUILTIN_ITEMS=$(item_count builtin)
EXT_FRONT=$(cat "$WORK/ext-front.txt"); BUILTIN_FRONT=$(cat "$WORK/builtin-front.txt")

echo "hidden applications with items: $EXPECTED"
echo "external: panel x=${EXT_PANEL_X:-none}, $EXT_ITEMS images, front $EXT_FRONT, after leaving: $(head -1 "$WORK/ext-after.txt")"
echo "built-in: panel x=${BUILTIN_PANEL_X:-none}, $BUILTIN_ITEMS images, front $BUILTIN_FRONT, after leaving: $(head -1 "$WORK/builtin-after.txt")"
FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "hover on the external bar opens the Ice Bar there" "[ -n '$EXT_PANEL_X' ] && [ '${EXT_PANEL_X:--1}' -ge 0 ]"
check "hover on the built-in bar opens the Ice Bar there" "[ -n '$BUILTIN_PANEL_X' ] && [ '${BUILTIN_PANEL_X:-0}' -lt 0 ]"
check "the external Ice Bar shows every hidden application's items" "[ $EXT_ITEMS -ge $EXPECTED ] && [ $EXPECTED -gt 0 ]"
check "the built-in Ice Bar shows every hidden application's items" "[ $BUILTIN_ITEMS -ge $EXPECTED ] && [ $EXPECTED -gt 0 ]"
check "opening the Ice Bar keeps the front" "[ '$EXT_FRONT' = '$EXT_APP' ] && [ '$BUILTIN_FRONT' = '$EXT_APP' ]"
check "the Ice Bar closes after the pointer leaves" "grep -q '^none' '$WORK/ext-after.txt' && grep -q '^none' '$WORK/builtin-after.txt'"
echo "work: $WORK"
exit $FAILED
