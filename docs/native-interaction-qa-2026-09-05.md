# Native interaction review — 2026-09-05

Target: `/Applications/Ice.app`, `0.12.0-macos27.103 (1302)`, arm64.
Device: macOS 27.0 `26A5425a`, built with the local Xcode-beta SDK.
Source branch: `codex/macos-27`. These edits have not been pushed to GitHub.

## Scope and implementation

Ice handles only its own status-button action/context menu on macOS 27. There
is no Notification Center forwarding, synthetic swipe, assessment restriction,
global mouse/hover/scroll listener, automatic outside-click rehide, or compositor
freeze. Native status items handle their own input.

Layout is the only code path that posts native Command-drags. It keeps one
desired order, shows the preview immediately, verifies the physical permutation
twice, and stops after bounded corrections. It does not write other apps'
position preferences. Clock, Control Center and the recording privacy indicator
are excluded from movable/hidden items.

Original screenshot pixels are used for Layout; no app icons, substitute SF
Symbols, hand-drawn fan glyphs or background color-keying remain. The captured
menu-bar background is intentional. Small glyphs have equal 52-point slots.

## Observed device checks

| Check | Evidence and result |
| --- | --- |
| Native hiding | Display, App Volumes and Macs Fan Control conceal together; one normal-sized Ice control stays at the boundary. Verified in builds 1296 and 1300/1301. |
| Native clock | AXPress on the system clock opens the actual Notification Center window; the Ice state and concealed icons stay unchanged. Pressing again closes the native window. Verified in builds 1300 and 1302. This is not a simulated swipe. |
| Runtime input hooks | `Tests/NativeInputAudit.swift` enumerates zero Ice-owned event taps, including during Layout editing, in builds 1299–1302. Source guards also prevent the NSEvent monitors from being constructed on macOS 27. |
| Cross-three-icon drag | Real Layout mouse drag moved Text Input over Wi-Fi, Spotlight and Battery in both directions. Native order committed in build 1300. |
| Cross-section drag | Spotlight Hidden → Visible → Hidden and two consecutive round trips passed in build 1301. Generations 1, 2, 6 and 7 committed; no failure messages. |
| Measured move confirmation | Isolated Spotlight moves in build 1301 took 0.76–0.80 s from the logged native move start to committed physical verification. This is a sample on this device, not a latency guarantee. |
| Cancelled drop | Dragging a Layout item outside all rows left the original row/order intact in build 1300. |
| Always-Hidden | Fan moved into and out of Always-Hidden. Expanding Hidden revealed App Volumes while Fan stayed concealed. Test items were restored to Hidden and the original disabled Always-Hidden setting restored. |
| Reopen/persistence | Restart into build 1301 retained Spotlight in Hidden and its physical order. It was then restored to its original Visible position. |
| Repeated toggles | Two rounds of 10 own-button AX presses alternated correctly; each snapshot contained exactly one Ice control. |
| Toggle video | The authoritative recording overlaps the second round, 09:27:10–09:27:20. Samples every 250 ms show stable expanded/collapsed endpoints and no delayed second transition. Native system fade/reflow remains; Ice adds no animation or frozen-frame workaround. The earlier 12-second recording did not overlap clicks and is not acceptance evidence. |
| Permissions/signing | Stable ad-hoc designated requirement `identifier "com.jordanbaird.Ice"`; no private-key/Keychain use and no TCC reset or permission changes during this review. |

The final build 1302 changes comments/formatting and limits the new slot width
to macOS 27; its macOS 27 behavior matches the tested 1301 implementation.
Installed bundle version/architecture and strict code-signature validation passed.
Its fresh process (PID 56466 at the final check) runs from `/Applications/Ice.app`.

## Remaining acceptance work

- The automation system rejects hardware-style right clicks on out-of-process
  system menu items (`elementIsOOPButExpectedToTargetAppAndNoEligibleParentElementWasFound`).
  Manual right-click testing of Wi-Fi and other third-party items is still needed.
  It must not be reported as passed merely because the event hooks were removed.
- The repeated-toggle test was about one click per second, not a high-frequency
  hardware mouse burst. Video sampling does not prove the absence of every
  single-frame native transition.
- Multi-display, fullscreen, menu-bar auto-hide and crowded/notched layouts on
  other display sizes have not been validated. Native available space remains a
  constraint; there is no proxy icon panel to bypass it.
- Older macOS releases were not runtime-tested in this pass.

## Reproducing the input-hook audit

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swiftc Tests/NativeInputAudit.swift -o /tmp/ice-native-input-audit
/tmp/ice-native-input-audit
```

The script is read-only and asserts exactly one Ice process and zero owned event
taps. `Tests/NativeStatusItemProbe.swift` separately reproduces native width-based
overflow. These are diagnostic scripts, not a replacement for device interaction QA.

During diagnosis MenuBarAgent was restarted once manually to exclude stale probe
state. That did not fix the boundary issue; fresh, consistent Ice-owned identities
did. The app never restarts MenuBarAgent, and the subsequent acceptance checks did
not restart it.
