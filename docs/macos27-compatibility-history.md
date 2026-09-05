# macOS 27 compatibility history (through build 1291)

The assessment restriction and Notification Center gesture implementation below
was rejected and removed in build 1292. This is a historical test record, not
the current design. See [current status](../MACOS27.md).

This fork contains an experimental compatibility layer for macOS 27, where
menu bar items are no longer exposed as independent WindowServer windows.

## What changed

- Menu bar items are discovered through each running application's
  `AXExtrasMenuBar` accessibility tree.
- Stable synthetic IDs preserve layout assignments across refreshes and app
  relaunches.
- Clicking Ice's permanent menu-bar button toggles only the items assigned to
  Hidden or Always Hidden. Ice itself and the core system controls stay visible.
- Clicking empty menu-bar space does not toggle sections on macOS 27, even if
  an older Ice installation left `Show on click` enabled. The permanent Ice
  button is the only menu-bar click target for revealing or concealing items.
- Right-clicking Ice's own button opens its menu. The legacy global
  empty-space context menu is disabled on macOS 27, even if its saved setting
  is enabled, so it cannot replace another menu-bar item's context menu. Its
  unsupported settings toggle and appearance-editor tip are also omitted.
- Hidden and always-hidden sections use a runtime-loaded MenuBarClientCore
  visibility restriction. Replacement restrictions overlap briefly so the
  menu bar is never unrestricted between two restricted hide/reveal states.
  When no items need hiding, including in Layout, no assertion is retained.
- While items are concealed, ordinary clock clicks use Notification Center's
  native edge-gesture input after validating the live clock target. The gesture
  controller has no access to Ice's visibility state: it cannot release an
  assertion, reveal a section, move icons, or suspend screen composition.
  Modified clicks, drags, right-clicks, and other menu-bar items are untouched.
  On macOS 27, scrolling over the clock also never shows/hides Ice sections,
  even when `Show on scroll` is enabled; that preference is otherwise preserved.
  Ice's **Notification Center** menu entry provides the same independent input
  for accessibility testing/users whose AX press produces no mouse event.
- Ice's permanent control item is placed through MenuBarAgent's
  `TrailingItemPreferredPositions` preference at the boundary between Visible
  and Hidden. Positions remain stable while toggling, avoiding icon movement.
- The legacy Hidden and Always-Hidden divider status items are not published on
  macOS 27. The permanent Ice toggle is the only Ice item in the menu bar, so
  section changes do not create duplicate icons or reserve empty slots.
- Item images are cropped from MenuBarAgent's composite hosting window, with
  Accessibility-derived menu bar symbols and text used when Screen Recording
  is unavailable. The layout never substitutes the owning application's icon.
- Screen Recording is optional on macOS 27. Ice does not request it during
  startup or ordinary hide/reveal operations, and permission checks are cached
  instead of polling TCC on every layout refresh.
- The obsolete macOS 26 item-attribution XPC service is not started on macOS 27.

## Limitations

- The hiding API is private and loaded defensively at runtime. A later macOS 27
  update may rename or remove it; Ice then fails open instead of collapsing the
  menu bar.
- Notification Center can ignore clock clicks while the visibility restriction
  is active. Explicitly allowing its bundle does not avoid this system-side
  effect. The native edge gesture remains usable with concealed items on the
  tested system. This route also uses runtime-resolved private APIs and depends
  on the system accepting Notification Center gestures. A rejected gesture
  leaves hiding unchanged; there is deliberately no release/reapply fallback.
  System keyboard shortcuts are not remapped.
- Third-party hiding is bundle-granular. If one application publishes multiple
  status items, Ice keeps the whole bundle visible when any sibling is assigned
  to the Visible section.
- Only the nine system items exposed by Apple's internal system-item allowlist
  can be controlled independently. While a hidden section is concealed, the
  attached Now Playing and Audio/Video extras follow macOS's visibility
  restriction and may temporarily disappear; revealing the section restores
  them.
- Revealing a section waits briefly for its replacement visibility restriction
  to activate before retiring the old one. This prevents full-bar flicker.
- Reordering restarts the system-managed MenuBarAgent process so it reloads its
  preferred positions; macOS relaunches it automatically.

## Notification Center regression — 2026-09-04

Build `0.12.0-macos27.83 (1282)` opened the panel by temporarily releasing the
visibility assertion, then restoring it. Although post-click AX snapshots
looked correct, the user observed hidden icons expanding during the click.
That transaction is rejected and removed; a composition hold is not isolation.

The user verified that the real two-finger right-edge swipe opens Notification
Center while icons remain hidden on macOS 27.0 (26A5425a). The replacement
routes clock clicks to that independent input, not to a hiding transition.

Local builds use `/Applications/Ice.app`, Release arm64, with the same ad-hoc
designated requirement. Builds through `0.12.0-macos27.89 (1288)` did not open
Notification Center with constructed gesture samples. Changing the CGEvent
tap or location alone did not fix it.

- The physical gesture was captured on 2026-09-04 at 23:57:40–41: CGEvent type
  31, FluidTouchGesture HID type 27, flavor 1, opening motion 9, closing motion
  1, positive progress, and phases 1/2/4 in the high option byte. Notification
  Center logged successful opening/closing without a visibility transition.
- The initial constructor populated only HID data. A no-input AppKit bridge
  test then exposed phase=None and amount=0 in the NSEvent envelope. Build
  `0.12.0-macos27.87 (1286)` also populates the envelope phase, amount, axis,
  gesture type, and timestamp. Runtime testing still did not open the panel;
  this fixed the bridge representation but was not sufficient for delivery.
- A second capture on 2026-09-05 at 00:20:38–40 exposed missing envelope data:
  opening motion is 9 in CGEvent field 123 as well as in HID; field 134 carries
  the phase and field 138 carries the Notification Center flavor. Delta and
  velocity also need coherent representations. Field 169 is the raw HID
  timestamp, not the nanosecond CGEvent timestamp. The constructor now uses a
  public HID-system event source without copying device IDs or source PIDs.
- Build `0.12.0-macos27.90 (1289)` successfully opened the actual system panel
  through Ice's independent entry at 00:24:41. Notification Center logged
  gesture start/end and `visible: true`; its actual AX window was present.
  The menu bar still contained only the intended visible items. No visibility
  restriction release/replacement occurred during the operation.
- The native-clock control experiment bypassed Ice's NSEvent mouse listener:
  AX press did not open the panel while concealed, but the same press opened
  it after Ice's explicit reveal removed the restriction. This is a side
  effect of the hiding API, not an attempt to reorder the clock. The clock
  remains in `MenuBarItemTag.immovableItems` and cannot be hidden in Layout.
- Build `0.12.0-macos27.91 (1290)` removes the temporary sampler and records the
  desired panel state when a clock click begins (or before Ice's menu opens).
  A native dismissal before mouse-up must not be misread as a request to reopen.
  Actual repeated physical clock-click QA is still required.
- The installed .91 build passed two independent-entry open/close cycles;
  Notification Center was visible without any restriction release/replacement.
  Four Ice-button toggles returned to the expected hidden state after AX
  convergence; only one Ice icon remained. Wi-Fi retained its native right-click
  menu and Layout rendered the six expected symbols without a permission warning.
  MenuBarAgent stayed at PID 1173 and the preferred-position hash was unchanged.
- Build `0.12.0-macos27.92 (1291)` additionally excludes the clock from legacy
  show-on-scroll handling. Other show-on-scroll behavior/preferences are unchanged.
- Event-construction checks pass for eight phase/direction samples and twelve
  invalid-input cases without posting input. Checks now include AppKit phase,
  amount and axis, and CGEvent serialization/HID retention.
- The failed panel-open attempt did not release or replace Ice's restriction.
  The MenuBarAgent PID and preferred-position hash remained unchanged.
- Ice's own button still reveals/conceals the managed items.
- The temporary gesture-only 90-second sampler from build .89 is removed from
  .91. No Keychain prompt, TCC reset, system preference change, or system-binary
  patch is part of this approach. No new input-capture permission is requested.

## Attribution

The macOS 27 Accessibility enumeration, assessment-mode bridge, and
MenuBarAgent preference approach were adapted from the GPLv3
[Thaw project](https://github.com/thaw-app/Thaw). Ice and these changes remain
licensed under GPL-3.0.
