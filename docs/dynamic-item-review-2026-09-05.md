# Dynamic and withdrawn menu-bar items

Date: 2026-09-05. This is a source-level fix and a targeted test plan, not a
claim that upstream [#666](https://github.com/jordanbaird/Ice/issues/666) or every
SwiftBar plugin has passed installed-build validation.

## Reproduced source defects

1. The macOS 27 provider used `identifier ?? description ?? title` as item
   identity. For a status item without an AX identifier, changing `CPU 20%` to
   `CPU 80%` produced a new tag and synthetic window ID despite the same live
   element. Display content was incorrectly an identity input.
2. `MacOS27MenuBarController` retained an absent Hidden tile indefinitely while
   its owner application remained alive. A plugin host can intentionally remove
   its final status item without exiting. The retained snapshot also entered
   `knownItemsForReordering`, leaving a stale potential drop target.

## Scope of the fix

- Third-party items without an AX identifier receive a process-local identity
  keyed by owner PID/launch date and equality of their AX object. Labels and
  coordinates do not affect the token. Existing explicit identifiers and the
  system/Text Input paths are preserved.
- Equality uses `CFEqual`, not Swift wrapper pointer identity. Apple documents
  [AXUIElement's support for Core Foundation equality](https://developer.apple.com/documentation/applicationservices/axuielement_h).
  That does **not** guarantee that a destroyed/recreated hosted status-item
  scene compares equal. Unequal objects are not guessed to be the same based on
  their label or position.
- The registry holds at most 512 AX references and removes unavailable owner
  lifetimes on ordinary scans. It deliberately has no time-to-live: an item
  missing from AX during long concealment must not change identity just because
  time passed. Tokens include a random Ice-session prefix. Their saved assignments
  are discarded on restart; the real menu bar supplies the new classification.
- Equal hosted variants at identical bounds are deduplicated. Conflicting
  bounds for one runtime identity are omitted from actionable provider output;
  their raw presence still prevents declaring that item withdrawn.
- The existence reread includes off-bar/zero-size published children that the
  ordinary actionable provider filters out. AX overflow is not withdrawal.
- Missing items are retained during concealment and reordering. In expanded
  snapshots containing Ice, two observations at least two seconds apart request
  a targeted owner reread. This is a grace period, not proof of withdrawal.
  Only a successful owner enumeration that lacks the identity retires it.
  Runtime-token assignments are removed with their expired tile; deterministic
  identifiers retain saved order for later republishing.
- A failed owner read, failed frame read, or failed identifier read does not
  establish absence. AXSwift returns `nil` for `noValue`/`attributeUnsupported`;
  a missing extras menu bar is a completed empty read. For `notImplemented`,
  the provider additionally requires a successful attribute-list read that
  omits `AXExtrasMenuBar`. `cannotComplete` and other failures retain the tile.

There are no changes to the native bar's positions, global input listeners,
screen-capture permissions, another application's preferences, or normal
show/hide interactions in this patch. Extra owner rereads occur only after an
expanded missing-item grace period, grouped once per owner namespace.

## Checks completed

- `Tests/MacOS27DynamicItemStateTests.swift`: 30 assertions pass, including the
  old description-key counterexample, label updates, reversed enumeration,
  duplicate labels, unequal recreated elements, owner-lifetime separation,
  capacity/owner cleanup, long concealment, session isolation, off-bar existence
  versus actionable geometry, and conceal/reorder grace resets.
- Two separately created AX application handles for the **test process itself**
  compare into the same registry token. This does not query another app, request
  permission, or prove the behavior of a live status-item scene.
- Current provider plus the real `AXHelpers.swift` typechecks against small
  dependency stubs; all changed production files parse. This does not replace a
  full application build.
- Scoped strict SwiftLint and `git diff --check` pass.

Reproduce the pure checks:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -parse-as-library Ice/MenuBar/MenuBarItems/MacOS27DynamicItemState.swift \
  Tests/MacOS27DynamicItemStateTests.swift -o /tmp/ice-dynamic-item-tests
/tmp/ice-dynamic-item-tests
```

## Controlled installed-build test still required

`Tests/DynamicStatusItemProbe.swift` is compiled and ad-hoc signed at
`/tmp/ice-dynamic-status-probe/IceDynamicProbe.app`, bundle ID
`local.ice.DynamicStatusItemProbe`. The producing agent did not launch it.
It creates only its own normal window and one status item; no event taps,
capture APIs, permission prompts, or preference writes are present.

1. Launch the probe and open Ice Layout. Record the probe's AX identifiers and
   initial tile to confirm it actually exercises the unidentified-item path.
2. Click **Rename** repeatedly. The same native status item changes its title
   and accessibility label. Confirm the tile remains singular, keeps its
   section and position, and displays the new content after capture refresh.
3. Click **Withdraw**. The final status item is removed, but the window and host
   process remain alive. With Ice expanded, allow two cache observations and
   check the stale tile disappears. Confirm no dead drop target remains.
4. Click **Restore**. This publishes a newly created status item. Its tile must
   return once and agree with the native position, without restoring an obsolete
   runtime assignment.
5. Check normal hiding/revealing while the item exists, then use **Quit** to
   remove all probe UI and its owned item. No real third-party icon needs to be
   command-dragged for this test.

Record exact installed build and pass/fail results before changing the upstream
feedback table from unvalidated. A live SwiftBar plugin may recreate its AX
element during a rename; this prototype tests one specific same-element case.

## Installed 1326 findings and follow-up candidate

The main testing agent subsequently exercised the controlled app on installed
build **1326**. Rename retained one runtime token (suffix `.3`), and Withdraw
cleared the tile after normal foreground Layout refreshes. **Restore failed to
return the tile over multiple five-second periods without reopening Layout.**
Launching the probe after Layout was already open also failed to discover the
new app. These are recorded failures, not an accepted dynamic-item feature.

The refresh scope was rebuilt from `knownItemsForReordering()` on every tick.
Correctly removing the last ghost tile also removed its owner from future AX
reads. The existing workspace publisher triggered a refresh on app launch, but
the refresh still read only the old item-derived owner list.

The follow-up candidate separates the current tiles from the Layout-session
owner scope:

- Entering Layout seeds a session registry from known owners. Successful
  snapshots add published owners; an empty or retired tile list does not remove
  its living host. Repeated entry callbacks do not reset the session.
- The **existing** workspace publisher supplies the application-list delta
  before its existing cache trigger. Only newly launched app lifetimes join the
  session; no new polling or AX observer is installed.
- Owner identity includes PID, namespace and available launch time. Direct
  PID refreshes require a currently matching lifetime; retained namespaces let
  the existing provider resolve an observed app's restart.
- The `isLayoutEditing` lifecycle clears the session only when editing actually
  ends. Closing the pane during a reorder leaves the session until that reorder
  finishes, following the controller's existing deferred-close behavior.
- The existing five-second tick reads the session's target owners, not every
  running process. A normal Layout entry still performs its existing full scan.

Discovery boundary: a process already running before Layout opens, with **no
status item observed**, can later publish its first item without launching a new
process. That produces neither a known-owner target nor an app-launch delta.
This deliberately scoped implementation discovers it on the next Layout entry
(or the existing full-load retry when available), not by scanning all apps every
five seconds. This limitation is distinct from a previously observed plugin
host's Withdraw/Restore, which the candidate now keeps in scope.

`Tests/MacOS27LayoutOwnerTests.swift` adds **15 passing assertions** for zero-item
retention, launch-only additions, unchanged application-list notifications,
PID/lifetime reuse, namespace restart support, explicit full-refresh discovery,
and session reset. The original **30 dynamic-item assertions still pass**.
The actual controller and helper typecheck with small dependency stubs; changed
production source parses and passes scoped strict SwiftLint. The follow-up
candidate still needs a full build and installed Rename/Withdraw/Restore test.
