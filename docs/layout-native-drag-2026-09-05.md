# Layout and native drag follow-up — installed-device record

## Requested behavior

- A compact, left-aligned Layout page with identifiable real menu-bar glyphs.
- No invisible/reserved positions before the first item. Empty row space is an
  append target, and an empty section has one explicit drop destination.
- Native Command-drag to the left of the visible Ice button must agree with
  the actual hidden boundary, without global input monitoring or click proxies.

## Installed build

`0.12.0-macos27.107 (1306)` is built, installed and running from
`/Applications/Ice.app` (Release arm64). Its ad-hoc designated requirement is
`identifier "com.jordanbaird.Ice"`; strict, deep signature verification passed.
Build log: `/tmp/ice-layout-native.3D8DaD/build-1306.log` (`BUILD SUCCEEDED`).
Earlier installed development bundles were moved to build-numbered backup
directories under `/tmp/ice-layout-native.3D8DaD` before replacement.

The Layout changes add section descriptions/counts, leading-aligned labelled
thumbnails, a clear insert marker, hover/drag feedback without animation,
clipping-aware drop hit testing, no-op drops, and Escape cancellation. There are
no fixed blank slots on the left; remaining row space is a real drop destination.
An unavailable capture shows its item name and a pending thumbnail instead of
an invisible slot. The empty-section hint is driven by the parent's observed
cache so it disappears immediately after a successful drop.

## Real glyphs without opaque screenshot blocks

Captures remain the input; the UI no longer draws their menu-bar material as
rectangular tiles. `MenuBarGlyphImage` estimates that material from the image
perimeter and separates the actual foreground. Monochrome glyphs become alpha
masks tinted with the system label color; colored glyphs use color-to-alpha
unmixing. No app icons, guessed SF Symbols or vector replacements are involved.
If extraction fails, the previous usable image remains, or a named pending
thumbnail is shown. This is not a claim of direct access to other apps' artwork.

All 21 synthetic assertions passed, covering four dark/light backgrounds,
transparency, solid and one-pixel strokes, sparse glyphs, colored foregrounds and
empty captures. Six real captures (App Volumes, Macs Fan Control, Wi-Fi, battery,
Spotlight and Text Input) produced usable monochrome masks, and their rendering
was inspected in the installed Layout page. Faint native glass edge remnants on
some system glyphs remain a possible refinement; arbitrary wallpapers and every
third-party colored icon have not been exhaustively accepted.

## Native drag investigation

The visible Ice item and `Ice.NativeBoundary.hidden.v2` are separate native
items. Live inspection found the blank item to the right of Ice, causing the
expanded blank to conceal Ice itself. Layout now checks the pair's live order
and, only if needed, moves Ice's own narrow blank immediately left of its button
using the existing bounded native drag. The blank is enabled for native dragging
only while editing Layout and has no click target/action.

The corrected pair was observed at blank x=1349 (width 3) and Ice x=1358
(width 28). Hiding then concealed the two intended third-party extras while
leaving one Ice arrow. The order survived the build 1306 relaunch. The user also
confirmed the Ice arrow was visible. Missing visible snapshots are retained
while concealing, so temporary AX disappearance does not discard a known item.

An isolated probe showed that widening the visible control removes its glyph
from the physical bar; this is not a viable replacement for a small Ice button.
Keeping a separate native spacer remains necessary. Resetting its autosave name
also failed to move it physically; that attempted approach was removed.
Temporary probe source and screenshots are under
`/tmp/ice-layout-native.3D8DaD`, not part of the app target.

## Installed-device checks

- The user unlocked the device and live QA resumed; the earlier lock-screen
  block is no longer current.
- Native Ice-button activation revealed/concealed the intended extras, with one
  Ice control. Ten consecutive activations alternated states in 8.6 seconds.
  This is state/order evidence, not frame-by-frame proof of zero flicker.
- Native clock activation opened the actual Notification Center while Ice
  stayed hidden. No gesture simulation or click forwarding was involved.
- The read-only event audit found zero Ice-owned event taps.
- Wi-Fi moved from the first Layout position across several items into the
  trailing empty area, then back to the left edge. AX order agreed afterward.
- App Volumes and Macs Fan Control moved between Visible and Hidden, including
  emptying Hidden and dropping back into that empty section. Build 1306 repeated
  that roundtrip; the empty-state hint disappeared correctly. All four desired
  order generations committed, with no operation-failed alert observed.
- Original test membership/order was restored: Visible Wi-Fi, battery, Spotlight,
  Text Input; Hidden App Volumes, Macs Fan Control. Later user changes are not
  overwritten by the test procedure.
- Build, scoped SwiftLint, `git diff --check`, glyph assertions and signature
  verification passed. No commit or push was performed for this follow-up.

## Remaining acceptance

Direct human Command-drag of a different app to the left of Ice **outside Layout
has not been verified**. The available UI drag tool cannot reliably hold Command
through that gesture. The repaired spacer order is necessary but is not proof
that this entire user flow is fixed. To accept it, close Layout, expand Ice,
Command-drag a movable item immediately left of Ice, then hide/show and compare
the actual menu bar with Layout membership. No global drag listener was added.

System-item hardware right clicks, multi-display, fullscreen and frame-level
flicker acceptance remain separate device checks. No password, Keychain, TCC,
security setting or other application's position preference was changed.
