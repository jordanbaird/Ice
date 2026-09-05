# GitHub feedback review: macOS 27

Date: 2026-09-05, Asia/Shanghai. This is an in-progress development record,
not a stable-release or zero-bug acceptance.

Historical rapid-toggle checkpoint: build **1324** was installed. At that
checkpoint the temporary fullscreen probe had been closed and its test border
restored off; fullscreen round-trip acceptance remained pending. The
[rapid-toggle follow-up](rapid-toggle-review-2026-09-05.md) records its latency
improvement and remaining native-fade failure. These are historical observations,
not the current installed build or acceptance of later candidates.

The later lifecycle review independently confirms **1326**
(`0.12.0-macos27.127`) installed and running at `/Applications/Ice.app`. It includes
a fix preventing Ice's boundary from being withdrawn while its synthetic native
drag still holds mouse/Command input; 20 pure state-sequence tests pass. Actual
1326 drag/cancellation stress is not yet validated. The
[lifecycle checkpoint and corrected crash chronology](review-2026-09-05.md#later-checkpoint-native-drag-lifecycle-protection-in-1326)
explain why this separate fix does **not** close the four earlier MenuBarAgent
crashes. In particular, the fourth crash also followed a later CC local drag;
the earlier inference that it excluded a CC-related trigger was incorrect.

Earlier build statements below describe their respective investigation
checkpoints. Neither installing a newer build nor fixing a separate race closes
the remaining feedback without its own evidence.

## Source and publication state

Public GitHub issue bodies, comments, PR metadata and selected PR patches were
read without posting, closing, committing or pushing anything. The fork
`PWB97/Ice` has issues disabled. The upstream
[macOS 27 PR #980](https://github.com/jordanbaird/Ice/pull/980) is open with no
conversation comments, inline comments or reviews at this check. Its head, and
the live `origin/codex/macos-27` branch, are still
`b949870a34084c33ac8a1a87d6cc5561f20ec990`.

Most relevant feedback is on upstream issues against older Ice releases, not
against the current local application. Local fixes must not be described as
already available to those commenters. Linked third-party scripts and suggested
permission resets were not executed.

## Feedback disposition

| Report | Evidence and current disposition |
| --- | --- |
| [#954: macOS 27 hiding, stretching and loading](https://github.com/jordanbaird/Ice/issues/954) | Reports primarily concern 0.11.13-dev.2 and early macOS 27 betas. The local native-boundary implementation has prior installed-build coverage for hiding, repeated toggles and direct drags; see the 1311 review. This is not proof that every variant in the thread is fixed, or that the published PR includes the current code. |
| [#965: Layout spins indefinitely](https://github.com/jordanbaird/Ice/issues/965) | Confirmed code defect: the old empty cache UI only had a spinner, with no completed-empty or timeout outcome. Added explicit loading, empty-result and timeout states plus a retry button. The timeout is eight seconds of the view task's scheduling time; it does not cancel a synchronous system AX call. Candidate builds pass compilation. Empty/timeout UI branches still need device verification without changing TCC permissions. |
| [#973: blank Layout on macOS 26](https://github.com/jordanbaird/Ice/issues/973) | The current macOS 27 capture and transparent-glyph path had installed 1311 coverage. This does not validate the older macOS 26 report or every display configuration. The new empty-state handling provides an actionable failure state instead of an empty disabled layout. |
| [PR #967: invalid average color](https://github.com/jordanbaird/Ice/pull/967) | Reproduced in local code: excluding every pixel caused division by zero and non-finite color components. Fixed zero-count handling; also reject non-finite thresholds before integer conversion. Three baseline assertions failed; all nine color assertions now pass. Added the analogous empty-count guard to gradient averaging. |
| [#959: appearance remains in fullscreen](https://github.com/jordanbaird/Ice/issues/959), [PR #975](https://github.com/jordanbaird/Ice/pull/975) | Reproduced locally through 1324. The root cause was an incorrect C-to-Swift Space-type return declaration, not an established missing-notification problem. Fixed the raw integer ABI and removed the temporary 250 ms Space polling. Installed **1326** passed two native fullscreen round trips with Border enabled on this single display; the same overlay hides in fullscreen and returns on the desktop. This validates the current local Border case, not every appearance mode, display arrangement, older macOS report, or the published PR. |
| [#970: automatic hiding](https://github.com/jordanbaird/Ice/issues/970) | Timed/outside-click automatic rehide is intentionally not restored on macOS 27. This user's contract is explicit Ice-button toggling and native input for every other item. Manual hiding and failure to hide must be distinguished from an intentionally omitted interaction. |
| [#947: Ice Bar crash](https://github.com/jordanbaird/Ice/issues/947), [#977: expander crash / update prompt](https://github.com/jordanbaird/Ice/issues/977) | Several old 0.11.12 macOS 26 reports share Ice main-thread SIGTRAP offsets. The current macOS 27 path skips the legacy XPC setup and does not enable the old Ice Bar. That removes those paths from this target, but is not validation of a general macOS 26 crash or Sparkle fix. The reports are also distinct from this machine's MenuBarAgent input-loop crashes. |
| [#666: changing/withdrawn SwiftBar items](https://github.com/jordanbaird/Ice/issues/666) | The local changing-label identity and withdrawn-ghost defects are now fixed. A controlled NSStatusItem probe passed same-item Rename on 1326, then Withdraw/Restore in one open Layout session on installed 1327; the latter exposed and fixed a separate lost-owner discovery bug. 30 identity/grace and 15 owner-session assertions pass. This is not yet validation of arbitrary real SwiftBar plugins that rebuild their AX scenes. See the dynamic-item and consolidated records. |
| [#966: unofficial macOS 26 build discussion](https://github.com/jordanbaird/Ice/issues/966) | Read for context; not a reproducible current macOS 27 failure. |
| [PR #984: capture permission rechecks](https://github.com/jordanbaird/Ice/pull/984) | Not copied. Periodically querying shareable capture content can itself interact with permission prompts, contrary to the explicit request to avoid recurring prompts. Keep the cached permission check and explicit request path; stale TCC entries are not repaired by repeatedly prompting. |

## Changes and checks

- `CGImage+AverageColor.swift`: extracted the existing implementation so it can
  be tested directly, with zero-count and invalid-threshold guards. The ordinary
  averaging algorithm remains unchanged. Nine assertions pass.
- `MenuBarOverlayGeometry.swift`: rejects absent, negative, non-finite or
  screen-exceeding frames. Nine assertions pass, including a secondary display's
  negative/nonzero origin. Those are geometry tests, not multi-monitor UI QA.
- `MenuBarLayoutSettingsPane.swift`: empty and timed-out loads expose an active
  retry button. There is no disabled/blurred empty row covering the retry control.
- Native boundary and glyph extraction tests were rebuilt from the current
  source: 16 and 21 assertions pass. Total: **55 passing assertions**.
- Release arm64 build **1317**, version `0.12.0-macos27.118`, succeeded with
  Xcode-beta on macOS `27.0 (26A5425a)`. Scoped strict SwiftLint and
  `git diff --check` pass. The full build still emits existing warnings elsewhere;
  no claim of a warning-free repository build is made.

## Fullscreen reproduction and build 1326 acceptance

`Tests/AppearanceFullscreenProbe.swift` creates a normal native fullscreen-capable
AppKit window. It adds no status item, input tap, capture session or permission
request. A read-only WindowServer audit records Ice's overlay visibility and
the display's actual Space type before and after using the window's fullscreen
button.

The 1311 baseline had a visible 1728-by-38 overlay remaining in fullscreen. An
intermediate attempt rejected a real macOS 27 menu bar because AX hit-testing
its origin returned `AXWindow`; that was corrected to use the visible native
WindowServer menu-bar window on macOS 27. Normal desktop appearance was then
restored, but later fullscreen tests still showed the panel on screen.

The initial interpretation of the 1315 logs was a notification-timing problem:
Ice reported a non-fullscreen Space even after a native fullscreen transition.
That interpretation is **withdrawn**. The app's fullscreen Boolean depended on
the incorrect bridge described below, so those logs did not establish that a
notification was early or missing. Build 1317 temporarily added a deduplicated,
per-display check every 250 ms while optional appearance panels existed. It did
not fix the underlying type conversion; 1324 still showed the border in a raw
type-4 Space. The polling has now been removed rather than retained as a
workaround for that mistaken diagnosis.

At the historical 1315 checkpoint, device testing stopped when the Mac locked
and the UI tool could not unlock it.
No attempt was made to bypass the lock. At that point:

- `/Applications/Ice.app` was still **1315** (`0.12.0-macos27.116`), PID 62060,
  with its strict ad-hoc signature verified. Build 1317 is built, not installed.
- The test window had exited fullscreen but remained open. The temporary
  appearance Border setting was still on; all other appearance effects were off.
  Restore Border off and quit the probe after manual unlock.
- MenuBarAgent remained PID 59001, started at 11:57:23. No new Ice/MenuBarAgent
  crash report was found; the same four earlier reports remain in `Retired`.
- No real menu-bar item was script-dragged in this GitHub follow-up. Original
  test-icon order was not changed. The separate Wi-Fi drag has not been approved.

### Confirmed raw-type ABI defect

`Shared/Bridging/Shims.swift` declared the C function `CGSSpaceGetType` as
returning the Swift enum `CGSSpaceType`. The enum's raw values are 0, 2 and 4,
but its compact Swift case tags are 0, 1 and 2. A `@_silgen_name` declaration
does not perform `RawRepresentable` conversion. The optimized old call compiled
to `CGSSpaceGetType` followed by a comparison with **2**, while WindowServer
returns **4** for fullscreen. Consequently the fullscreen predicate was false
in the actual fullscreen case and could misclassify raw type 2 instead.

The declaration now returns `UInt32`; `Bridging.isSpaceFullscreen` compares
with `CGSSpaceType.fullscreen.rawValue`. A test-only C fixture returns native
integer values 0, 1, 2, 3, 4, 5 and `UInt32.max`. All **14** ABI/classification
assertions pass. The explicit Swift function type also rejects a regression
back to the enum-return declaration at compile time. The fixture is outside
the Ice target and does not call WindowServer or mutate application state.

Build 1325 verified the ABI fix with the temporary poll still present. Build
1326 then replaced that poll with `NSWorkspace.activeSpaceDidChangeNotification`
and frontmost-application changes, reading the owning display's Space once
initially and on events. The existing fullscreen order-out and desktop re-show
handling remains. There is no recurring Space-query timer or new input monitor.
This removes the specific four-times-per-second query; it is not a claim of
zero background work or a measured whole-app energy improvement.

### Installed 1326 device acceptance and limits

The installed `/Applications/Ice.app`, version `0.12.0-macos27.127` (**1326**),
PID 67180, passed two native `AppearanceFullscreenProbe` round trips with only
Border temporarily enabled. The test used this Mac's single 1728-by-1117-point
display. The same Ice overlay Window ID **8049** was tracked across states:

| Device state | Native Space | Overlay audit and observed result |
| --- | --- | --- |
| First fullscreen entry | 985, raw type 4 | Overlay `onScreen` is omitted by WindowServer (`null` in the audit); the border is absent. |
| Return to desktop | 1, raw type 0 | The same overlay reports `onScreen: true`; the border returns. |
| Second fullscreen entry | 990, raw type 4 | The same overlay again has no on-screen flag; the border is absent. |

The probe was returned to the desktop and quit; Border was restored **off**.
The recorded field is `null`, not a fabricated `false`: WindowServer omits the
on-screen key for that off-screen window. The native visual checks and the
tracked window identity are both part of this acceptance.

The standalone Space-notification helper was an investigation aid only. Its
initial bare command-line run loop did not receive a notification in its short
sample; a later variant used a prohibited-activation `NSApplication` event loop.
Neither helper result establishes what the actual Ice process receives. The
event-driven decision above is based on **installed Ice 1326** succeeding during
the native transitions, not on assuming the helper models the app exactly.

Evidence: `/tmp/ice-consolidated.UDfQfH/1326-fullscreen.json`,
`1326-desktop-return.json`, and `1326-fullscreen-second.json`. The old comparison
is preserved in `/tmp/ice-rapid-toggle.8suOQF/space-enum-abi-proof.s`; the C/Swift
regression sources are `Tests/SpaceTypeBridgeFixture.c` and
`Tests/SpaceTypeBridgeTests.swift`.

This closes the reproduced **single-display Border/fullscreen case** locally.
Multiple displays, split/full shape and tint configurations, other macOS
versions and all variants of upstream #959 are not covered by these checks.
Rapid-toggle visual acceptance, the earlier MenuBarAgent crash finding and the
SwiftBar dynamic-item case remain separate and are not closed by this fix.

## Local evidence and recovery

### Consolidated 1327 follow-up

[The installed-build record](consolidated-qa-2026-09-05.md) supersedes the earlier
candidate statements for completed local checks. Build 1327 includes the dynamic
identity/owner lifecycle, drag critical-section and Space ABI fixes. It passed
142 pure checks, real Layout multi-icon order changes and two-way section moves,
and native clock activation while physically collapsed. A plain quit/relaunch
preserved tested order. Rapid overflow fade remains open; a current development
bundle is not proof that old macOS reports, untested display configurations or
the published remote PR contain these fixes.

The public #954 thread was refreshed through its September 4 update. Its latest
comment points to another macOS 27 implementation, pelmet. Its README/tree were
inspected, not installed or copied; the readme's private-API and animation
claims are not acceptance evidence for Ice. Linked scripts were not executed.
Issue #974's older macOS 26 orphan-window report explicitly lacked proof of
Ice causation, so it is not marked fixed by this macOS 27 work. No issue was
closed, comment sent or PR changed in this session.

### Isolated private menu-bar assertion diagnostic

The user separately authorized a bounded re-evaluation of the old menu-bar-only
`MBAssessmentModeConfiguration`/`MBAssessmentModeAssertion` interface. It is not
integrated into Ice. `Tests/NativeAssessmentVisibilityProbe.m` was compiled as
`/tmp/ice-consolidated.UDfQfH/AssessmentProbe.app` with GPL attribution, bundled
source/LICENSE, and strict ad-hoc signature verification. Preparation by the
review agent did not launch the probe or activate an assertion. The main agent
subsequently ran the explicitly authorized isolated test; it **failed** and the
approach was rejected. See the
[isolated assertion failure record](assessment-isolation-2026-09-05.md).

Startup only creates the probe's own window/menu/AV status item and checks API
availability. Explicit Hide requires exactly one running
`local.ice.DynamicStatusItemProbe` at
`/tmp/ice-dynamic-status-probe/IceDynamicProbe.app`. The allowlist includes all
other current running bundle identifiers, system item IDs 0–8 and protected
Apple hosts, including `com.apple.appkit.status-items` and
`com.apple.MenuBarAgent.systemservices`. If protecting broad hosts also prevents
selective hiding of the victim, that is a failed selectivity test; do not remove
the protections or expand scope without a new decision.

Reveal/AV/Quit, activation failure, process launch/termination notifications and
a 45-second main-queue watchdog invalidate the assertion. All private API calls
are on the main thread; completion callbacks return there and validate both
generation and lease identity before updating UI. A late old completion releases
its own assertion and cannot report newer intent as active. The watchdog is a
scheduled main-queue safeguard, not a guarantee under an unresponsive system.
No whole-computer assessment mode, screen-update suspension, event tap, click
proxy, position preference write or permission change is included. In the
isolated device test, both the victim and allowed AV icon disappeared, and one
native clock click (following two fresh target checks) failed while the assertion remained
ACTIVE. Reveal restored both icons, and the same clock click immediately opened
the native Notification Center. The probe was then quit, without relaxing the
protected hosts or adding click forwarding. This API path is **not** accepted
for Ice on the tested OS build and will not be integrated. The early failure
also means the 45-second watchdog was not runtime-validated by that run.

Build/test artifacts and preserved intermediate app bundles:
`/tmp/ice-github-review.0FGsWx`. Build cache:
`/tmp/ice-publish-build.usVY11`. The pre-follow-up application is preserved at
`/tmp/ice-github-review.0FGsWx/previous-build-1311.app`.

The previous accepted native interaction checks, earlier crash evidence and
test scope are in [the 1311 review](review-2026-09-05.md). Do not silently replace
those historical results with claims about an untested candidate.
