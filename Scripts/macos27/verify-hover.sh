#!/bin/bash
#
# Verifies hover detection on macOS 27:
#   1. hovering an empty spot of the external menu bar reveals the hidden section,
#   2. hovering a visible item there does not,
#   3. hovering the application menu there does not,
#   4. hovering an empty spot of the built-in menu bar reveals it, whether that bar
#      is inactive or active,
#   5. hovering the application menu of the active built-in bar does not.
#   6. no hover takes the front from the active application.
#
# A revealed section appears on every display, so each check reads the external
# bar: the built-in bar folds most items behind its overflow button.
#
# Requirements: Ice installed with Scripts/install.sh, Thaw not running, EXT_APP
# with a window on the external display and BUILTIN_APP with one on the built-in
# display. The application frontmost when the script starts decides the display
# Ice's icon lives on, so run it once with each display's menu bar active. Leave
# the keyboard and mouse alone: another application coming to the front moves the
# active menu bar, and a hover during which that happened is repeated.
#
# Usage: Scripts/macos27/verify-hover.sh <ext-empty-x> <ext-empty-y> <ext-menu-x> <builtin-empty-x> <builtin-empty-y> <builtin-menu-x>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_X="$1"; EXT_Y="$2"; EXT_MENU_X="$3"; BUILTIN_X="$4"; BUILTIN_Y="$5"; BUILTIN_MENU_X="$6"
EXT_APP="${EXT_APP:-Cursor}"
BUILTIN_APP="${BUILTIN_APP:-Slack}"
EXT_REGION="${EXT_REGION:-700,0,1220,34}"
IFS=, read -r EXT_REGION_X _ EXT_REGION_W _ <<< "$EXT_REGION"
WORK="$(mktemp -d /tmp/ice-verify-hover.XXXXXX)"
mkdir -p "$WORK/bin" "$WORK/frames"

swiftc -O "$ROOT/Scripts/macos27/pointer.swift" -o "$WORK/bin/pointer"
swiftc -O "$ROOT/Scripts/macos27/analyze-frames.swift" -o "$WORK/bin/analyze-frames"
swiftc -O "$ROOT/Scripts/macos27/ax-items.swift" -o "$WORK/bin/ax-items"

quit_ice() {
    osascript -e 'tell application id "com.jordanbaird.Ice" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null || return 0; sleep 0.25; done
}
front_app() {
    osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
}
activate() {
    osascript -e "tell application \"$1\" to activate" >/dev/null
    # Ice reads the items again about a second after an application activates.
    sleep 2.5
}
ensure_front() {
    [ "$(front_app)" = "$1" ] || activate "$1"
}
external_leftmost() {
    screencapture -x -R "$EXT_REGION" "$WORK/frames/$1.png"
    "$WORK/bin/analyze-frames" "$WORK/frames" "$EXT_REGION_X" "$EXT_REGION_W" | awk -v n="$1" '$1 == n { print $2 }'
}
# Hovers (x, y) coming straight up from (x, away-y) with APP frontmost, reads the
# external bar, and leaves. Prints -1 if APP kept losing the front.
hover_and_read() {
    local name="$1" x="$2" y="$3" away_y="$4" app="$5" value front
    for _ in 1 2 3; do
        ensure_front "$app"
        "$WORK/bin/pointer" glide "$x" "$away_y"; "$WORK/bin/pointer" hold 1
        "$WORK/bin/pointer" glide "$x" "$y"; "$WORK/bin/pointer" hold 1.5
        value=$(external_leftmost "$name")
        front=$(front_app)
        "$WORK/bin/pointer" glide "$x" "$away_y"; "$WORK/bin/pointer" hold 2
        if [ "$front" = "$app" ]; then
            echo "$value"
            return
        fi
        echo "note: $front came to the front during $name, repeating it" >&2
        echo "$front during $name" >> "$WORK/front-changes"
    done
    echo -1
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
defaults write com.jordanbaird.Ice UseIceBar -bool false
defaults write com.jordanbaird.Ice ShowOnHover -bool true
open "$HOME/Applications/Ice.app"
sleep 10

# The external menu bar is active.
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
ensure_front "$EXT_APP"
EXT_HIDDEN=$(external_leftmost ext-hidden)
EXT_REVEALED=$(hover_and_read ext-revealed "$EXT_X" "$EXT_Y" 540 "$EXT_APP")
ensure_front "$EXT_APP"
STATS_X=$("$WORK/bin/ax-items" | awk '/eu\.exelban\.Stats/ && $1 >= 0 { print int($1 + $3 / 2); exit }')
EXT_OVER_ITEM=$(hover_and_read ext-over-item "$STATS_X" 14 540 "$EXT_APP")
# The gap between two neighbouring items is part of the items' own run of the bar.
GAP_X=$("$WORK/bin/ax-items" | awk -v from="$STATS_X" '$1 ~ /^-?[0-9]+$/ && $1 > from { print $1, $1 + $3 }' | sort -n | awk 'NR > 1 { gap = $1 - prev; if (gap > 8 && gap < 40 && mid == 0) mid = int(prev + gap / 2) } { prev = $2 } END { print mid }')
EXT_OVER_GAP=$(hover_and_read ext-over-gap "${GAP_X:-0}" 14 540 "$EXT_APP")
EXT_OVER_MENU=$(hover_and_read ext-over-menu "$EXT_MENU_X" "$EXT_Y" 540 "$EXT_APP")
INACTIVE_BUILTIN=$(hover_and_read inactive-builtin "$BUILTIN_X" "$BUILTIN_Y" 589 "$EXT_APP")

# The built-in menu bar is active; the external bar is dimmer, so it gets a new baseline.
activate "$BUILTIN_APP"
"$WORK/bin/pointer" glide "$BUILTIN_X" 589; "$WORK/bin/pointer" hold 1
ensure_front "$BUILTIN_APP"
DIM_HIDDEN=$(external_leftmost dim-hidden)
ACTIVE_BUILTIN=$(hover_and_read active-builtin "$BUILTIN_X" "$BUILTIN_Y" 589 "$BUILTIN_APP")
BUILTIN_OVER_MENU=$(hover_and_read builtin-over-menu "$BUILTIN_MENU_X" "$BUILTIN_Y" 589 "$BUILTIN_APP")

echo "external active: hidden=$EXT_HIDDEN revealed=$EXT_REVEALED over-item=$EXT_OVER_ITEM (stats x=$STATS_X) over-gap=$EXT_OVER_GAP (gap x=${GAP_X:-none}) over-menu=$EXT_OVER_MENU built-in=$INACTIVE_BUILTIN"
echo "built-in active: hidden=$DIM_HIDDEN built-in=$ACTIVE_BUILTIN over-menu=$BUILTIN_OVER_MENU"
FAILED=0
# A value of -1 means the check could not run with the right application in front.
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "hover on the external bar reveals" "[ $EXT_REVEALED -ge 0 ] && [ $EXT_REVEALED -lt $((EXT_HIDDEN - 20)) ]"
check "hover over a visible item does not reveal" "[ $EXT_OVER_ITEM -ge 0 ] && [ $EXT_OVER_ITEM -ge $((EXT_HIDDEN - 3)) ]"
check "hover in the gap between two items does not reveal" "[ ${GAP_X:-0} -gt 0 ] && [ $EXT_OVER_GAP -ge 0 ] && [ $EXT_OVER_GAP -ge $((EXT_HIDDEN - 3)) ]"
check "hover over the application menu does not reveal" "[ $EXT_OVER_MENU -ge 0 ] && [ $EXT_OVER_MENU -ge $((EXT_HIDDEN - 3)) ]"
check "hover on the inactive built-in bar reveals" "[ $INACTIVE_BUILTIN -ge 0 ] && [ $INACTIVE_BUILTIN -lt $((EXT_HIDDEN - 20)) ]"
check "hover on the active built-in bar reveals" "[ $ACTIVE_BUILTIN -ge 0 ] && [ $ACTIVE_BUILTIN -lt $((DIM_HIDDEN - 20)) ]"
check "hover over the built-in application menu does not reveal" "[ $BUILTIN_OVER_MENU -ge 0 ] && [ $BUILTIN_OVER_MENU -ge $((DIM_HIDDEN - 3)) ]"
# Ice activating itself while showing items takes keyboard focus from the user's application.
check "no hover takes the front from the active application" "! grep -q '^Ice ' \"$WORK/front-changes\" 2>/dev/null"
[ -s "$WORK/front-changes" ] && sed 's/^/      front changed: /' "$WORK/front-changes"
echo "frames: $WORK/frames"
exit $FAILED
