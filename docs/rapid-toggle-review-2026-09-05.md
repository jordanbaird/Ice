# Rapid toggles keep the menu bar expanded

Date: 2026-09-05. Status: application-side delay improved; native overflow fade
still fails rapid-toggle visual acceptance. Rejected direct-toggle experiments
and a conservative production fast path are recorded below. **Final rapid-toggle
acceptance is pending.** Historical build/install statements are explicitly dated
checkpoints, not the final current installation state.

## Confirmed control-flow problem

In the implementation through build 1318, the native show operation withdraws
the blank boundary immediately. Every hide
operation, including a hide immediately after a previously successful hide/show,
republishes a narrow boundary and awaits `alignNativeHidingBoundary`.

That method unconditionally sleeps 200 ms before reading current owner AX
frames. Boundary insertion/reorder can add more time. A subsequent show cancels
the pending hide and removes its handle. Thus a sequence such as this never
physically hides while the clicks continue:

| Relative time | Requested operation | Physical result |
| --- | --- | --- |
| 0 ms | Hide | Still expanded; boundary verification pending |
| 80 ms | Show | Cancel hide; remain expanded |
| 160 ms | Hide | Start another 200 ms minimum wait |
| 240 ms | Show | Cancel again; remain expanded |

This is a code-derived schedule, not a measured hardware-click trace. It is a
control-flow defect, not an animation-duration defect. If an odd final hide is
left to settle it can eventually complete, but that does not make each preceding
click a visually intuitive toggle. No claim is made that all reported behavior
has a single cause.

Relevant code: `MenuBarManager.syncNativeVisibility`,
`cancelNativeConcealment`, and `MenuBarItemManager.alignNativeHidingBoundary`.

## Failure cleanup included in build 1318

The failed-alignment branch previously reset section state to shown without
withdrawing the temporary narrow boundary. Resetting a `ControlItem` state does
not call native visibility synchronization, so an empty native slot could remain.
The branch now explicitly withdraws both Ice-owned handles and resets the
controller's concealment flag before reporting expanded. Cancellation/generation
guards still prevent obsolete completions from changing a newer request.

At the pre-unlock checkpoint, build **1318** (`0.12.0-macos27.119`) passed Release
arm64 compilation and the changed manager passed scoped strict SwiftLint. It
had **not been installed**; `/Applications/Ice.app` was still build 1315 then.
This small failure-cleanup fix does **not** remove the ordinary hide delay.

## Direct-toggle experiment: initial plan before unlock

A coordinate/preference-cache shortcut was considered but not adopted: unchanged
Ice coordinates do not prove that a withdrawn boundary will be reinserted at the
right native position, particularly immediately after a Command-drag.

`Tests/NativeSingleItemToggleProbe.swift` instead tested the proposal that one
native toggle item could change its own width, attempting to keep its image at
the right edge using `imagePosition = .imageRight` and
`imageHugsTitle = false`. That placement was a hypothesis, not an accepted result.
The probe has no second
boundary, input monitor, AX scan, custom animation, task delay or reordering
routine. Actual mouse actions are restricted to its right-end icon slot, while
Command-drag and AX activation retain native handling. Only probe-owned test
items/preferences are created.

At the pre-unlock checkpoint the prototype had compiled; a separately identified,
ad-hoc signed app was ready at
`/tmp/ice-rapid-toggle.8suOQF/SingleItemProbe.app` but had **not been launched**.
Compilation does not prove that MenuBarAgent honors the image
placement, accepts the wide item, or leaves native hit-testing correct.

Had the experiment succeeded, production integration would also have needed the right-end
icon rectangle as the section boundary rather than the entire wide AX rectangle.
Otherwise concealed items' retained frames can be incorrectly classified as
visible. Layout must restore normal width before arranging items; existing
Always Hidden behavior cannot silently be removed. The prototype source lists
the visual, rapid-toggle, native-drag and system-item acceptance matrix.

`Tests/NativeIceToggleProbe.swift` provides a separate bounded AXPress timing
diagnostic for the exact installed Ice button (1–20 presses, 50–1000 ms interval).
It neither sends global mouse input nor modifies other items. It was compiled
to `/tmp/ice-rapid-toggle.8suOQF/native-ice-toggle-probe` but **not run at that
checkpoint**. Its
timestamps measure action acknowledgements, not physical render latency. Use
native mouse checks as well; an AX label is not evidence that items disappeared.

## Historical device blocker at the build 1318 checkpoint

The UI tool reported that the Mac was locked and could not unlock it. No attempt
was made to bypass the lock. Manual unlock was required before installed or
prototype UI tests could continue. Before that checkpoint, no app had been quit,
replaced or launched during the rapid-toggle follow-up; no menu-bar item had
been moved and no permission changed.

The earlier temporary fullscreen QA window and Border setting still required
cleanup at that point, as recorded in the
[GitHub feedback review](github-feedback-review-2026-09-05.md). The fullscreen
candidate, earlier MenuBarAgent crash finding and dynamic SwiftBar case remain
open; this follow-up does not resolve or replace those records.

The resumption plan was to restore temporary appearance settings, quit the
fullscreen probe, test the single-item experiment with Ice gracefully closed,
restore Ice, then either integrate a verified design or reject the experiment.

## Device results after manual unlock: direct-toggle routes rejected

The single-wide-item route was tested, not adopted. The variants below changed
only probe-owned status items; none became production hiding code.

| Variant | Tested change | Observed native result |
| --- | --- | --- |
| A | Native `imageRight` with `imageHugsTitle = false`; requested width was the menu-bar region minus 32 points. | The left test items disappeared, but the probe arrow disappeared too. The right-side items stayed in place. |
| B | A transparent padded template image instead of native cell alignment, retaining the region-minus-32 width. | The probe arrow still disappeared with the left test items. Image padding did not establish a usable toggle. |
| C / D | Bound the requested width using the probe item's own expanded trailing edge and available space; account for native padding and reserve an additional icon slot. | Only the system overflow chevrons (`<<`) remained where applicable, not a usable probe arrow. The narrower-width variants did not rescue the single-item route. |
| Separate zero-width boundary probe | Keep a custom view in a zero-width probe-owned boundary. | Hiding could work, but the expanded menu bar still reserved approximately 16 points of empty space. This failed the no-empty-slot requirement. |

The results do not establish whether every failure comes from image placement,
hosted clipping, or native overflow selection. Successful action acknowledgements
and retained AX elements are not proof that the arrow is visible. No independent
overlay, global click proxy or custom animation was added to compensate.

Both status-item probes were quit normally. The earlier fullscreen probe was
also quit and the temporary appearance Border setting was restored to **off**.
The existing fullscreen, MenuBarAgent crash and dynamic SwiftBar findings remain
separate; this cleanup does not mark them fixed.

## Production candidate 1319: live own-pair fast path

The existing two-item hiding structure remains. Build **1319** adds a narrowly
admitted check before the old mandatory 200 ms wait:

- Read only Ice's own current AX items on the main thread. Do not acquire the
  complete-provider scan lock, whose background owner may itself be waiting for
  the main thread.
- Reject distinct hosted frames for either exact control identifier before
  ordinary provider deduplication can hide the ambiguity.
- Validate the narrow boundary and Ice button on the display selected for this
  visibility operation: finite, same-row frames, narrow width no greater than
  three points and a gap from zero through six points.
- Require system hit-tests at both centers to agree with each item's exact
  identifier, current Ice PID and live frame. Re-read Ice's pair and reject any
  frame change.
- Admit only ordinary hiding while Layout editing is inactive and Always Hidden
  is disabled.
  Passing checks permit immediate widening without native dragging, another
  application's AX scan, or a complete membership-cache refresh. Physical order
  remains authoritative; normal cache reconciliation still occurs separately.
- Any failed condition uses the existing 200 ms settling/full-snapshot/alignment
  path. Existing cancellation and generation guards prevent a superseded hide
  from applying afterward.

The zero-to-six-point gap is a conservative local admission condition, **not a
standalone proof of global adjacency or a documented minimum third-party item
width**. System hit tests and frame checks are required as well. Native
cross-boundary reordering still needs regression coverage with the installed
candidate.

In the initial 1319 device sample, **four of six hide requests used the fast
path**; two still reached the fallback. This is a small observed sample, not a
guaranteed success rate or a measured end-to-end rendering latency. It does not
yet establish that every click in a rapid sequence is visually correct.

## Candidate 1320: bounded short rechecks, acceptance pending

At this record update, build **1320** (`0.12.0-macos27.121`) was being built. Its
fast-check phase permits up to two additional checks separated by **16 ms**
each, with cancellation checks, to give a just-republished hosted item a short
opportunity to settle. It does not wait those intervals when the first check
passes. If all three checks fail, the existing 200 ms safe path remains.

The total requested sleep in that phase is at most 32 ms, **excluding AX-call
time and scheduling overhead**; this is not a hard end-to-end latency bound.
Neither 1320 build completion nor installed/native rapid-toggle acceptance is
claimed here. Final installation state, repeated native-click results and
cross-boundary regression results must be added after the checks finish.

No commit, push, release or GitHub issue/PR comment was published in this round.

## Subsequent device checkpoint: 1321 hit-test failure and 1322 timing results

The following is an appended checkpoint, preserving the candidate records above.
The installed-build measurements and native regression results in this section
come from the main device-test trace in this session. They do **not** establish
final visual rapid-toggle acceptance.

Build **1321** still rejected an already-correct Ice-owned pair: its system-wide
hit test returned **Telegram PID 60645** while Ice's own current boundary/button
geometry was correct. The host's system-wide hit map and current owner geometry
were not aligned in that sample. This failed condition therefore sent an
otherwise-ready ordinary hide into the slower fallback.

Build **1322** removes that system-wide hit-test prerequisite **only from the
resize-only fast check**. It still checks current, unambiguous Ice-owned frames,
the same-row/narrow-boundary geometry, and an unchanged second owner read. The
fast path resizes only Ice's own status item and posts no input. Native drag
operations retain their actual input-target checks; this is not permission to
click or drag using unverified coordinates. The historical 1319 hit-test
requirements above describe that candidate, not the 1322 fast check.

| Installed 1322 test | Observed result | What the measurement does not prove |
| --- | --- | --- |
| 12 AX presses | All six hide requests took the fast path; the recorded fast-check durations were approximately **1.8–6.4 ms**. | AX acknowledgements and check duration do not measure physical disappearance. |
| 12 ordinary native left clicks, requested 120 ms spacing | Actual posted down-to-down spacing was approximately **126–135 ms**. All six hide requests took the fast path; recorded checks were approximately **1.7–2.3 ms**. | Successful posts and six completed hides do not prove that each intermediate visual transition finished before the next click. |

These are observed ranges, not hard performance bounds. They exclude the native
host's presentation/animation time. The unchanged safe fallback is still
available when the own-pair check cannot establish readiness.

Other checks in this device checkpoint:

- App Volumes was moved across Ice in both directions, then restored to the
  left of Macs Fan Control. The physical hidden/visible behavior followed the
  tested native placement.
- MenuBarAgent remained **PID 59001**, with no restart and no new relevant IPS
  crash report during these checks. This does not resolve the older recorded
  MenuBarAgent crash finding or prove crash-freedom outside the tested interval.
- Layout screenshots showed the expected order and transparent menu-bar glyphs.
- All **63** current pure-function assertions passed: native boundary **24**,
  glyph extraction **21**, average color **9**, and overlay geometry **9**.
- The input audit found **zero Ice-owned event taps**. The fast path introduced
  no global event monitor or event forwarding. This is not a claim that other
  applications or the operating system have no event taps.

## Visual acceptance still fails: native fade remains during fast clicks

The first six-second recording,
`/tmp/ice-rapid-toggle.8suOQF/1322-native-12x120ms.mov`, captured only the tail of
the click activity. Sequential decoding completed successfully with **25 real
samples**, but the pointer reached Ice only around **5.69 seconds**. Earlier
samples remained collapsed. This recording must **not** be used as evidence for
all 12 clicks. Uniform-time image-generator failures were not evidence that the
video could not be decoded sequentially.

The subsequent synchronized recording,
`/tmp/ice-rapid-toggle.8suOQF/1322-native-12x80ms-synced.mov`, was decoded offline
into **100 real frames**, retaining their actual presentation timestamps rather
than inventing evenly spaced frames. During this run, actual native click
spacing was approximately **90–116 ms**. The recorded images still showed faded
icon remnants between clicks: the icons did **not** become completely hidden
after each hide request before the following show request.

Consequently, **1322 is not accepted as satisfying the user's immediate,
visually clear toggle requirement**. The repeated cancellation/200 ms wait
problem is improved in the measured runs, but that control-flow improvement is
not sufficient while the native fade continues to overlap subsequent clicks.
Final state parity, fast-path logs, pure-function tests and successful native
reordering cannot replace this visual check.

At this appended checkpoint, source build **1323** was a temporary
no-animation-transaction candidate being built and **had not been installed**.
Its effect on hosted native rendering is unverified. No claim is made that the
candidate removes the fade, preserves every interaction, or is ready for final
installation. The fullscreen and other separately recorded open findings remain
open. This documentation update makes no installation or publication change.

## Build 1323 animation transaction experiment: rejected

1323 was subsequently installed and run. It wrapped Ice-owned `length` and
`isVisible` changes in an `NSAnimationContext` with zero duration and disabled
implicit animation, plus a `CATransaction` with actions disabled. It did not
change system preferences or send input to other applications.

The synchronized six-second recording
`/tmp/ice-rapid-toggle.8suOQF/1323-native-12x80ms-synced.mov` decoded into **108
actual frames**. Faded icon remnants still appeared during the clicks. The local
transaction did not suppress the native host's overflow transition. SDK review
also found no documented per-status-item switch for that host animation;
thread-local layer transaction settings do not promise cross-process effects.
This is not proof that all possible native implementations are exhausted.

The ineffective animation wrapper was removed, rather than retained as
unverified compatibility code. Build 1324 keeps the resize-only fast check and
failure cleanup, without timing notices, extra animation transactions or global
input monitors. It is an incremental latency improvement, **not acceptance of
instantaneous rapid toggling**. The current withdrawn-boundary/overflow approach
still needs an implementation-level solution to the demonstrated native fade.

## Final installation checkpoint for this session

Build **1324**, `0.12.0-macos27.125`, passed the Release arm64 build, was staged
and ad-hoc signed without Keychain access, then installed at
`/Applications/Ice.app`. Strict deep signature verification passed. The running
bundle was checked at **PID 65246**, and the installed-build input audit again
reported **zero Ice-owned event taps**. MenuBarAgent remained **59001**. No
single-item, zero-boundary or fullscreen probe app was left running; the
temporary appearance border had been restored off. The previous installed
1323 bundle is retained under the explicit session backup directory.

1324 differs from the tested resize-only 1322 behavior by removing temporary
timing logs; it does not claim to eliminate the demonstrated native fade. The
user began interacting with Ice during the final window-cleanup step, so no
additional automated mouse sequence was run concurrently with that input.
No GitHub commit, push, comment, issue closure, permission reset or Keychain
authorization was performed in this follow-up. The other open review findings
remain open, and this is not a stable-release or zero-bug claim.

## Subsequent isolated experiments: native input remains mandatory

The zero-width boundary probe was additionally tested with its button view
hidden while expanded (`--hide-view-when-expanded`). The macOS 27 host still
reserved a 16-point slot. `hidden-view-expanded-settled.png` under
`/tmp/ice-consolidated.UDfQfH` records the settled result. This public-API variant
was not integrated, and the independent probe was quit.

The user then explicitly authorized an independent, bounded retest of the
private menu-bar assessment assertion, not its integration into Ice. Ice was
quit for this test. The assertion again failed the native-clock contract:
the same freshly validated physical clock click opened Notification Center
before/after the assertion, but not while it was active. It also hid the
allowed diagnostic's own AV button. The assertion was released immediately;
both test buttons and native clock behavior recovered, and the probe was quit.
See [the isolated assertion record](assessment-isolation-2026-09-05.md).

No proxy, simulated swipe, new global input monitor, whole-computer assessment
mode or compositor suspension was added to work around this failure. The
native overflow fade remains an explicitly open implementation limitation;
the unrelated dynamic-item and fullscreen fixes do not close rapid-toggle
visual acceptance.
