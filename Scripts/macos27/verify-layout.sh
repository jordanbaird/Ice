#!/bin/bash
#
# Verifies the Menu Bar Layout window on macOS 27: while it is open every item is shown;
# dragging an item into the Hidden row moves its application to the Hidden section, which
# is concealed after the window closes and stays so after Ice restarts. The layout is
# restored afterwards.
#
# Requirements: Ice installed with Scripts/install.sh, EXT_APP with a window on the
# external display, TEST_LABEL/TEST_BUNDLE naming a visible application with a menu bar
# item. Leave the mouse and keyboard alone.
#
# Usage: Scripts/macos27/verify-layout.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_APP="${EXT_APP:-Safari}"
TEST_LABEL="${TEST_LABEL:-Pritunl}"
TEST_BUNDLE="${TEST_BUNDLE:-com.electron.pritunl}"
REGION="700,0,1220,34"
WORK="$(mktemp -d /tmp/ice-verify-layout.XXXXXX)"
mkdir -p "$WORK/bin" "$WORK/steady"
for tool in pointer input layout-ax analyze-frames; do
    swiftc -O "$ROOT/Scripts/macos27/$tool.swift" -o "$WORK/bin/$tool"
done
# Only the layout key is saved and put back. Exporting the whole domain and importing it
# again carried any earlier damage forward: a second run saved the already-changed layout
# as its "before" and restored that, which is how a real layout was lost once.
as_bool() { case "$1" in 1|true|YES|yes) echo true ;; *) echo false ;; esac; }
ORIGINAL_ICE_BAR=$(as_bool "$(defaults read com.jordanbaird.Ice UseIceBar 2>/dev/null || echo 1)")
LAYOUT_BEFORE=$(defaults read com.jordanbaird.Ice MacOS27Layout 2>/dev/null || echo "{}")

quit_ice() {
    osascript -e 'tell application id "com.jordanbaird.Ice" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null || return 0; sleep 0.25; done
}
activate() { osascript -e "tell application \"$1\" to activate" >/dev/null; sleep 2.5; }
external_leftmost() {
    screencapture -x -R "$REGION" "$WORK/steady/$1.png"
    "$WORK/bin/analyze-frames" "$WORK/steady" 700 1220 | awk -v n="$1" '$1 == n { print $2 }'
}
start_ice() {
    open "$HOME/Applications/Ice.app"
    for _ in $(seq 1 40); do pgrep -x Ice >/dev/null && return 0; sleep 0.25; done
}
# Leave Ice running, the way the run found it. A run that ended with Ice down left the
# machine concealing nothing, and whatever was looked at next showed nothing worth seeing.
restore() {
    quit_ice
    defaults write com.jordanbaird.Ice MacOS27Layout "$LAYOUT_BEFORE"
    defaults write com.jordanbaird.Ice UseIceBar -bool "$ORIGINAL_ICE_BAR"
    local after
    after=$(defaults read com.jordanbaird.Ice MacOS27Layout 2>/dev/null || echo "{}")
    if [ "$after" = "$LAYOUT_BEFORE" ]; then
        echo "PASS  the saved layout is back as it was"
    else
        echo "FAIL  the saved layout was left changed; it was:"
        printf '%s\n' "$LAYOUT_BEFORE"
    fi
    start_ice
}
trap restore EXIT

quit_ice
defaults write com.jordanbaird.Ice UseIceBar -bool true
open "$HOME/Applications/Ice.app"
sleep 10
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
BEFORE=$(external_leftmost before)

# Reopening Ice shows its settings; select Menu Bar Layout.
open "$HOME/Applications/Ice.app"
sleep 3
"$WORK/bin/layout-ax" > "$WORK/settings.txt"
SIDEBAR=$(awk '/^sidebar/ { print $2, $3; exit }' "$WORK/settings.txt")
if [ -n "$SIDEBAR" ]; then
    "$WORK/bin/pointer" glide ${SIDEBAR}; "$WORK/bin/pointer" hold 0.3
    "$WORK/bin/input" click
fi
sleep 4
OPEN_LEFTMOST=$(external_leftmost layout-open)
"$WORK/bin/layout-ax" > "$WORK/layout.txt"
SOURCE=$(awk -v l="$TEST_LABEL" '$1 == "image" && $2 == 0 && index($0, l) { print $3, $4; exit }' "$WORK/layout.txt")
TARGET=$(awk '$1 == "image" && $2 == 1 { print $3, $4; exit }' "$WORK/layout.txt")
echo "layout window: sidebar=${SIDEBAR:-none} source=${SOURCE:-none} target=${TARGET:-none}"
if [ -n "$SOURCE" ] && [ -n "$TARGET" ]; then
    "$WORK/bin/input" drag ${SOURCE} ${TARGET}
fi
sleep 3
STORED=$(defaults read com.jordanbaird.Ice MacOS27Layout | sed -nE "s/^ *\"?${TEST_BUNDLE//./\\.}\"? = ([0-9]);/\1/p")
"$WORK/bin/input" close-window
sleep 3
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
AFTER_CLOSE=$(external_leftmost after-close)
quit_ice
open "$HOME/Applications/Ice.app"
sleep 10
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
AFTER_RESTART=$(external_leftmost after-restart)
STORED_AFTER_RESTART=$(defaults read com.jordanbaird.Ice MacOS27Layout | sed -nE "s/^ *\"?${TEST_BUNDLE//./\\.}\"? = ([0-9]);/\1/p")

echo "before=$BEFORE layout-open=$OPEN_LEFTMOST after-close=$AFTER_CLOSE after-restart=$AFTER_RESTART stored=${STORED:-none} stored-after-restart=${STORED_AFTER_RESTART:-none}"
FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "every item is shown while the layout window is open" "[ ${OPEN_LEFTMOST:-9999} -lt $((BEFORE - 20)) ]"
check "dragging into the Hidden row moves the application to Hidden" "[ '${STORED:-}' = 1 ]"
check "the moved application is concealed after the window closes" "[ ${AFTER_CLOSE:-0} -gt $((BEFORE + 10)) ]"
check "the move survives a restart" "[ '${STORED_AFTER_RESTART:-}' = 1 ] && [ ${AFTER_RESTART:-0} -gt $((BEFORE + 10)) ]"
echo "work: $WORK"
exit $FAILED
