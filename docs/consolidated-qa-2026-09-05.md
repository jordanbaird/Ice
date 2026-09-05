# Consolidated follow-up: installed build 1327

This is an incremental development checkpoint, not a zero-bug or stable-release
claim. The explicitly open native overflow fade prevents rapid-toggle visual
acceptance. No new GitHub publication was performed in this session.

## Bundle and automated checks

- `/Applications/Ice.app`: `0.12.0-macos27.128 (1327)`, Release arm64.
- Full Xcode-beta build succeeded after production files were frozen; strict
  deep ad-hoc signing passed. No Keychain or TCC reset was used.
- Previous bundle retained at
  `/tmp/ice-consolidated.UDfQfH/previous-build-1326.app`.
- Recompiled checks: boundary 24, drag-visibility lifecycle 20, glyph extraction
  21, average color 9, overlay geometry 9, C/Swift Space ABI 14, dynamic identity
  30, Layout owner lifecycle 15: **142 passing assertions**.
- Installed input audit: zero Ice-owned event taps. MenuBarAgent remains PID
  59001; Ice was PID 68158 at the first 1327 check.

## Changes included

1. Protect the exact synthetic drag input critical section from boundary
   withdrawal; after releasing mouse/Command, apply the latest requested state.
   This closes a code-level cancellation race, not the unproven root cause of
   four older MenuBarAgent crashes.
2. Identify unidentified dynamic items by bounded process-lifetime/AX equality,
   not their changing labels. Retire withdrawn tiles only after a grace period
   and successful owner reread. Keep the Layout session's owner discovery
   independent of the last tile, including newly launched app lifetimes.
3. Correct the private Space function's C return ABI to its raw integer. The
   previous Swift enum declaration compared native fullscreen value 4 with a
   Swift case tag 2. Remove the ineffective 250 ms fullscreen polling.

## Device evidence and limits

- Installed 1326 passed two single-display native fullscreen round trips with
  Border enabled. The same overlay disappeared in fullscreen and returned on
  the desktop. Border was restored off; 1327 includes the unchanged production
  fix. Other appearance modes and physical multi-display setups are untested.
- Installed 1327 native clock click opened Notification Center with Ice still
  hidden. Screenshots `1327-clock-hidden-before.png` and
  `1327-clock-hidden-after.png` both show App Volumes/Fan absent; window count
  changes 7 to 8, adding the native 1728-by-1117 Notification Center window.
  Clicking the clock again closes it. Only window existence/bounds were
  inspected, never notification contents. The earlier 1326 test proves no
  toggle while expanded, not while hidden: the initial arrow interpretation
  was reversed (`chevron.left` is hidden, `chevron.right` is visible).
- The authorized isolated assessment assertion failed: native clock input
  stopped working while it was active and recovered after release. It also hid
  the allowed diagnostic's own button. The probe was quit and no production
  integration, click proxy or simulated gesture was added. See
  [the precise isolation record](assessment-isolation-2026-09-05.md).
- A zero-width, hidden-button-view probe still left a 16-point hosted slot;
  it was rejected. The current expanded/Layout boundary remains withdrawn.
- Physical order was unchanged across the ordinary 1326-to-1327 replacement:
  App Volumes, Ice, Macs Fan Control, then the other visible items. A prior
  mixed probe/quit/relaunch sequence changed the relative Ice/Fan position;
  its cause is not established, so ordinary replacement parity is not proof of
  all restart scenarios.

Dynamic-owner, Layout/native reorder, and final cleanup outcomes are recorded
below. Successful API acknowledgements alone
do not constitute physical rendering or order acceptance.

## Installed 1327 Layout results

- Dynamic probe Withdraw removes the last stale tile while its process stays
  running. Restore returns one tile in the same open Layout session, without
  navigating away/reopening. The analogous Restore test failed on 1326. Probe
  Quit also removes its tile. Same-element Rename identity passed on 1326;
  recreation remains a new runtime identity rather than a label-based guess.
- Macs Fan Control Visible to Hidden moved physically left of Ice.
- Three immediately consecutive Spotlight Move Right actions crossed Wi-Fi,
  Battery and Text Input. Layout and screenshot agree on the final order, with
  Spotlight at x1508. Three Move Left actions restore x1384 and the original
  visible order. This is real Layout action/worker QA, not a mouse-gesture test.
- App Volumes Hidden to Visible, then Visible to Hidden, then Move Left restore
  all passed: final native x1170 (Vol), x1208 (Fan), x1238 (Ice), x1384 (Spotlight).
  No operation error appeared. The final idle Layout has no blank leading tile;
  labelled glyph cells share 88-point widths and 96-point horizontal pitch.
- Closing Layout restores hiding. The next real Ice click reveals; a subsequent
  click hides. Arrow meaning and physical icon presence are checked together.

The control acknowledgements are sub-millisecond in the recorded Layout tests,
but physical movement/convergence takes longer. These acknowledgements are not
reported as the end-to-end response time. Full build warnings on unrelated
legacy task-handling paths remain; this is not a warning-free build claim.

## Normal restart and cleanup checkpoint

After restoring App Volumes/Fan to the left, a plain 1327 quit/relaunch preserved
their side and order. Ice returned at x1238, Spotlight x1384, and its own saved
Visible.native.v1 position remained 347. The launch was initially collapsed;
one real Ice click revealed App Volumes x1170 and Fan x1208. Ice's PID changed
from 68158 to 68702 by this deliberate restart, not a crash. MenuBarAgent stayed
59001. Thus the earlier mixed assertion/probe sequence's position anomaly did
not reproduce in this controlled ordinary restart.

At the post-Layout idle snapshot, Ice used 0.0% sampled CPU and about 109 MiB RSS;
this is one sample, not a CPU benchmark. The appearance audit found no remaining
overlay or extra unnamed Ice status windows. No new Ice/MenuBarAgent `.ips`
report was found: the four September 5 agent reports remain the old 11:56–11:57
reports, not resolved crash root causes.

The ordinary right-clock click was also target-validated and paired. It did not
open an Ice window/context menu or alter the expanded state. No separate native
clock context menu appeared in this check, so this proves only the absence of
Ice interception, not every right-click behavior of every system item.

## Native Command-drag acceptance

Four scoped real Command-drags ran outside Layout on installed 1327. Each used
fresh source/target AX identity, containing native WindowServer menu-bar bounds,
paired release cleanup and six seconds of post-drag observation:

1. App Volumes moved right of Ice. After an actual Ice hide click, App Volumes
   remained physically visible and Fan disappeared (`1327-native-volume-stays-visible.png`).
2. After reveal, App Volumes moved back left of Fan, restoring x1170/x1208/x1238.
3. Spotlight moved left of Ice. After hide, Spotlight and the existing Hidden
   items disappeared (`1327-native-spotlight-hidden.png`); unrelated visible
   items remained visible.
4. After reveal, Spotlight moved back right of Ice. Its original position after
   Telegram/Now Playing is restored via two Layout Move Right actions.

All four completed with the same MenuBarAgent PID 59001 and no operation error.
They do not close the old unidentified CC local-drag crash, every possible
concurrent cancellation case, or rapid rendering acceptance. The synthetic
drag critical-section state tests cover cancellation sequencing separately.

The initial safer diagnostic stopped without a mouse drag when its geometry
guard incorrectly required MenuBarAgent ownership of the Menubar window. The
real owner was verified as the system WindowServer executable, layer 24. A
subsequent attempt stopped after releasing its own Command key because HID
state also included the script's injection; this was not evidence of user
input or a production failure. The final tool permits only its own already-held
left Command/left button, rejects other inputs, bounds input holding, and
requires no concurrent user automation. Same-key human/script overlap cannot
be distinguished, and the tool does not claim otherwise.

## Final handoff

Spotlight's two Layout moves restored the original full visible order. The
final physical order and Layout agree: Hidden = App Volumes, Macs Fan Control;
Visible = Telegram, Now Playing, Spotlight, Wi-Fi, Battery, Text Input. Clock
and Control Center are fixed and not editable Layout items. The expanded native
bar has a single Ice arrow and no idle leading blank boundary button.

Layout was closed to end thumbnail capture, then Ice was explicitly collapsed.
All temporary probe apps are quit; Border remains off. The installed/running
bundle is 1327 at `/Applications/Ice.app`, PID 68702, arm64, strict signature
verified. The final input audit still reports zero Ice event taps. No other
app's preferences were rewritten, no MenuBarAgent restart, Keychain prompt,
permission reset or GitHub mutation was performed.

Still open: rapid overflow fade, the root trigger of the four older system
agent crashes, real SwiftBar rebuild variants, multi-display/fullscreen modes
beyond the tested single-display Border case, and all possible interactive
cancel/timing combinations. These limits are not hidden by the passing tests.
