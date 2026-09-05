# macOS 27 native interaction

Current installed development build: `0.12.0-macos27.128 (1327)` at
`/Applications/Ice.app`. It removes the unnecessary full wait and stale hit-map
prerequisite from ordinary, settled-pair hiding, and cleans up failed hiding
handles. **Rapid-toggle visual acceptance still fails:** the current native
overflow implementation can leave fading icons during approximately 90–116 ms
clicks. The zero-duration animation experiment did not fix this and was removed.
See the [rapid-toggle investigation](docs/rapid-toggle-review-2026-09-05.md) for
recorded-device evidence, rejected experiments and the remaining limitation.
See the
[GitHub feedback review](docs/github-feedback-review-2026-09-05.md) for exact
per-report status. Single-display Border fullscreen round trips now pass after
fixing the C/Swift Space-type ABI; the temporary polling was removed. The
[consolidated installed-build record](docs/consolidated-qa-2026-09-05.md) covers
dynamic-item retirement/rediscovery, native-drag lifecycle protection, 142 pure
checks, real Layout ordering and native Notification Center acceptance.
The authorized private hiding retest again broke native clock input and was
[rejected](docs/assessment-isolation-2026-09-05.md), not integrated. Temporary
probe apps are closed and the temporary appearance border is restored off.
Build 1311 is the preceding native-interaction review baseline.
See the [native interaction review](docs/native-interaction-qa-2026-09-05.md)
and the [Layout follow-up and acceptance record](docs/layout-native-drag-2026-09-05.md).
The [direct native-drag follow-up](docs/native-boundary-drag-2026-09-05.md)
records the build 1307 boundary fix separately from Layout acceptance.
The [current review and installed-build checks](docs/review-2026-09-05.md)
record the empty-slot fix, lifecycle/performance changes and crash investigation
for builds 1308–1311.
The user accepted both direct Command-drag directions and native Notification
Center on build 1307. System-item hardware right clicks, multi-display and other
fullscreen appearance configurations remain unverified. Four system MenuBarAgent input-loop crashes were
found during the test interval; their trigger remains unresolved, so this is not
a stable-release acceptance. Controlled follow-up drags did not reproduce those
crashes; see the current review for the evidence and remaining test coverage.

## Interaction contract

- Ice's own status button handles its left click and context menu.
- Other menu-bar buttons receive native input. In particular, the clock opens
  Notification Center without forwarding, simulated gestures or Ice callbacks.
- No macOS 27 global mouse, hover, scroll, outside-click or timed-rehide monitors.
- No assessment restriction, visibility assertion or compositor suspension.
- Other applications are moved only by explicit Layout actions. A request to
  hide may additionally issue one bounded native drag of Ice's own blank
  boundary immediately left of its own visible button, if their order differs.
  The app does not rewrite other applications' position preferences or restart
  MenuBarAgent.
- Clock and Control Center are fixed, unhideable, and never drag sources.

## Implementation

A normal-sized Ice control and an Ice-owned blank status item form the boundary.
Both use fresh native identities instead of the experimental hosted positions.
Hiding changes the blank item's width to fit the native status region; an
arbitrary oversized width such as 10,000 is discarded by macOS 27.
Revealing withdraws the blank item: even a one-point native item reserves a
visible slot. Layout also withdraws it while idle. A hide request temporarily
reinserts the narrow handle and reads fresh Ice-owned geometry. An unambiguous,
stable narrow pair on the same display can resize directly; wider gaps, custom
spacing and unsettled frames use the full ordering check. System hit testing
is required for actual input delivery, not for resizing our own item.
Reinsertion can restore an obsolete position after manual
Command-drags; if needed, Ice moves only its own blank immediately left of its
visible button. A source hit test must identify that exact Ice-owned boundary
before any such drag. Ice then updates membership
from that current order and widens the blank. An item dragged to the right stays
visible; one dragged anywhere left of Ice is on the concealed side, including a
drop between the previous blank position and Ice. Hiding does not depend on
whether the previous cache already contained a Hidden item.

The same pair check runs for an explicit Layout reorder, not merely for opening
the page. Resetting the status item's autosave name did not repair physical order
and is not used. There is no global drag listener. Native Ice actions run on
mouse-up; a newer expand request cancels any
pending concealment. Failed boundary verification leaves items expanded instead
of hiding the wrong side or Ice itself.

Layout maintains one desired order and serializes native drags. It publishes
the requested preview immediately, verifies the live order twice, and only then
commits section membership. It no longer combines native drags, guessed
preference weights, neighbor-swap fallbacks and a frozen compositor.
Both verification stages compare ordinal positions: hosted hit areas may overlap
by a few points even when their native order is correct. Corrections are bounded.
Dragging inside Layout uses local view mouse events and an insertion marker;
the source remains in its original view until mouse-up. Dropping outside a row
cancels without removing the item. A drop goes directly to its requested neighbor.

Thumbnail input comes from the composited screenshot API, cropped using current
AX frames. Application icons and semantically reconstructed symbols are not used
as substitutes. Frames are checked again after capture to reject images raced by
a move. Capture is limited to Layout, so concealed items cannot overwrite their
thumbnails with pixels belonging to a different visible item.

Layout capture is single-flight and coalesces pending requests. A completed
capture is discarded if its editor/reorder generation changed. Entering Layout
refreshes all owners once; subsequent editing refreshes use a Layout-session
owner set, retained even after that owner's last tile is withdrawn. The existing
workspace observer adds newly launched process lifetimes. An already running,
previously unseen owner publishing its first item can still require reopening
Layout for discovery; no per-tick whole-process AX scan is added.
Off-menu-bar AX extras are excluded rather than displayed as ghost thumbnails.
Unchanged images, permission results and persisted layout state are not
republished or rewritten. These changes do not add a custom animation.

`MenuBarGlyphImage` separates the foreground from the sampled menu-bar material.
Monochrome glyphs become transparent masks rendered with the system label color;
colored glyphs retain their foreground colors. This is still pixel-derived,
not access to another app's vector artwork. Failed extraction retains the last
usable glyph, or shows a named pending thumbnail if none exists. Thin strokes,
sparse glyphs, light/dark backgrounds and colored glyphs have synthetic tests.
Layout uses leading-aligned, uniformly spaced 88-point labelled thumbnails.
There are no reserved blank slots at the left. An empty section has one explicit
drop destination, and the empty-state hint disappears as soon as it has an item.

## Review findings

1. Global and proxy input paths coupled unrelated menu-bar actions to Ice.
2. Assessment-style hiding also interfered with native clock activation.
3. The previous single-item, 10,000-point probe did not establish that native
   hiding was impossible: it had no controlled left-hand target.
4. Persisted position guesses could disagree with physical order. Mixing those
   writes with native drags caused overlap, snap-back and repeated failures.
5. Recreating the boundary lost its native ordering identity.
6. The old system-item allowlist omitted movable items such as Focus and Display.
7. Filtering all high-level windows from a display capture could remove real
   hosted status-item scenes, producing missing or wrong thumbnails.
8. Stream/window capture distorted hosted glyphs. The screenshot API preserves
   their real shapes. Rendering those captures unchanged left conspicuous
   material rectangles; foreground extraction now removes that background
   without substituting semantic replicas.
9. Pairwise ordinal verification disagreed with whole-layout rectangle tests for
   overlapping Text Input hit areas, creating a no-progress retry loop.
10. System dragging callbacks could discard a detached Layout view before its
    cancellation callback restored it. Local Layout dragging removes that path.
11. Redirecting every cross-section move to the boundary forced two drags and
    unnecessary verification timeouts before reaching the requested neighbor.
12. A blank boundary placed to the right of Ice could conceal Ice itself.
    Layout and hide requests now verify the order of these two Ice-owned items.
13. An empty-row hint read an unobserved cache and could remain after a drop;
    the parent now passes the observed empty state explicitly.
14. Layout-only boundary repair did not handle manual Command-drags outside
    Settings, and cached section counts could miss the first newly hidden item.
15. Off-bar or coincident overflow frames must not overwrite physical section
    assignments; a real item to the right of Ice can become Visible even while
    the left section is concealed.
16. Keeping a one-point blank published still reserved a visible native slot.
    Withdrawing it removes that gap; settling and hit-testing its reinsertion
    prevents stale geometry from selecting a neighboring real item.
17. An off-bar WeChat AX extra produced a blank Layout tile. Live enumeration
    now requires a positive-sized item in a real display's menu-bar strip.
18. Overlapping capture/refresh tasks could publish stale editor content.
    Cancellation, generation checks and single-flight capture bound that work.
19. Sidebar selection publishing during AppKit List updates produced SwiftUI
    render re-entry warnings. Publishing on the next main run-loop pass avoids
    the observed re-entry; equal values are ignored.
20. Optional appearance panels could survive after their effects were disabled,
    and failed panel updates could retry without yielding. Panels are reconciled
    on configuration changes and retry loops have bounded polling intervals.
21. A C function's raw Space type was declared as a Swift enum result, silently
    comparing native fullscreen value 4 with Swift tag 2. The bridge now returns
    UInt32; native Space/application events drive optional appearance updates.
22. Dynamic AX labels were mistaken for stable item identities. Unidentified
    items now use bounded process-local AX equality, and successfully confirmed
    withdrawals retire stale tiles without forgetting their Layout-session owner.
23. Cancelled concealment could withdraw an in-flight native drag's source.
    Boundary publication is now pinned through mouse/Command release, then
    reconciled with the latest requested visibility state.

## Reproducible checks

[NativeStatusItemProbe.swift](Tests/NativeStatusItemProbe.swift) is an independent
AppKit probe, not part of the application target. Compile with:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swiftc Tests/NativeStatusItemProbe.swift -o /tmp/native-status-probe
```

Package the executable in a normal macOS app bundle before launch. Verify the
physical order Left 2, Left 1, blank boundary, Probe. Quit Ice before isolating
the probe. Click Probe to alternate between native hiding and removal of the
blank item, then click the clock and inspect the actual Notification Center.
Use screenshots as well as AX: overflow children can briefly report identical
or stale frames.

The installed-build matrix must cover native clock and right clicks, rapid
toggles, Layout glyph/spacing parity, cross-section and multi-icon moves, and
restart persistence. Multi-display and fullscreen behavior require separate
device validation.

Run the foreground extraction checks independently of the app:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swiftc -O Ice/MenuBar/LayoutBar/MenuBarGlyphImage.swift \
  Tests/MenuBarGlyphImageTests.swift -o /tmp/ice-glyph-image-tests
/tmp/ice-glyph-image-tests
```

Run the native-boundary decision checks with:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swiftc -O Ice/MenuBar/MenuBarItems/MacOS27NativeBoundary.swift \
  Tests/NativeMenuBarBoundaryTests.swift -o /tmp/ice-boundary-tests
/tmp/ice-boundary-tests
```

These assertions do not replace a physical Command-drag acceptance test.

`Tests/NativeMenuBarDrag.swift` is a separate, opt-in real-device test tool, not
part of the app target. It only accepts the explicitly approved App Volumes,
Macs Fan Control and Spotlight sources, restores the cursor and releases input
on failure. Its snapshot/side checks can still observe stale AX data: validate
the converged native bar, hidden membership and all affected neighbors too.
Do not extend its allowed sources without the user's approval.

## Attribution and history

Accessibility enumeration was adapted from the GPLv3
[Thaw project](https://github.com/thaw-app/Thaw).
Earlier experimental approaches and device observations are retained in the
[historical test record](docs/macos27-compatibility-history.md); they are not the
current input or hiding implementation.
