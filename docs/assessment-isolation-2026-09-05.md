# Isolated menu-bar assertion test: rejected

Date: 2026-09-05, Asia/Shanghai. System: macOS 27.0 (`26A5425a`).

The isolated `MBAssessmentModeConfiguration` / `MBAssessmentModeAssertion`
experiment **failed the required native-click contract** and will not be added
to Ice. The protected configuration also hid the probe's own explicitly allowed
`AV` item, not just the intended victim. The response is to abandon this path,
not remove protected hosts, add a click proxy, or extend the test's scope.

## Isolation and scope

Ice was quit before the assertion experiment. The independent application was
`/tmp/ice-consolidated.UDfQfH/AssessmentProbe.app`, built from
`Tests/NativeAssessmentVisibilityProbe.m`. Its startup was `INACTIVE`; only the
explicit Hide action activated the assertion. No private assertion was installed
into or activated by production Ice.

The sole excluded bundle was `local.ice.DynamicStatusItemProbe`, running from
`/tmp/ice-dynamic-status-probe/IceDynamicProbe.app`. Every other current running
bundle was allowed. System IDs 0–8 and protected Apple hosts remained allowed,
including `com.apple.appkit.status-items` and
`com.apple.MenuBarAgent.systemservices`. The probe and Ice bundle identifiers
were explicitly allowed as well. These protections were not relaxed after the
failure.

The probe contains no whole-computer assessment session, WindowServer update
suspension, input tap, click forwarding, permission reset, position preference
write or other-app lifecycle control. The test's ordinary clock clicks were
sent only after fresh AX target verification; they are test input, not a proxy
implementation. Notification contents were not inspected. Window visibility and
geometry were used only to determine whether Notification Center opened.

## Observed sequence

| Phase | Evidence |
| --- | --- |
| Startup, 15:41:10.045 | Generation 1 logged `INACTIVE`. The native bar showed `AV` and `Dyn 2`. |
| Explicit Hide, 15:41:18.867 | Generation 2 logged API `ACTIVE`. Both `Dyn 2` and the explicitly allowed `AV` disappeared in the composited menu-bar screenshot. API completion was not treated as behavioral success. |
| Clock while ACTIVE | One ordinary down/up click was sent at `(1650, 16)`, after two fresh AX checks identified the exact native clock owned by MenuBarAgent PID 59001. The paired event sends completed, but the visible NotificationCenter-owned window count remained at its baseline of 7: the panel did not open. The probe still reported ACTIVE; no application-launch notification or watchdog had invalidated the assertion. |
| Immediate Reveal, 15:41:42.768 | Generation 3 logged `REVEALED`; `AV` and `Dyn 2` returned. The same native clock click then changed the visible window count from 7 to 8 and introduced the native 1728-by-1117 Notification Center window. A further clock click closed it. |
| Quit, 15:41:58.563–58.572 | Generations 4 and 5 logged quitting and application-termination cleanup. Subsequent process inspection confirmed probe PID 67478 had exited. |

The click target, system agent PID and location were held consistent across
ACTIVE and REVEALED. The lack of a lifecycle-triggered release during the ACTIVE
checks matters: the successful post-Reveal click cannot be misreported as native
click compatibility while the assertion was active.

A separate control check with installed Ice 1326 also opened Notification Center
(visible count 7→8) without changing Ice's expanded state. Its control retained
its starting `Forward` AX description. The native image mapping is visible =
right chevron (`Forward`), hidden = left chevron (`Back`); the earlier summary
reversed these labels. This 1326 check therefore does **not** establish that Ice
remained collapsed. It is independent evidence for the current non-assessment
implementation's unchanged expanded state, not acceptance of this rejected
prototype. The later, separately screenshot-verified 1327 collapsed-state clock
check is recorded in the [consolidated follow-up](consolidated-qa-2026-09-05.md);
it does not retroactively change the 1326 test's starting state.

## Cleanup and diagnostic audit

A read-only audit at 15:42:15 confirmed that the assertion probe was no longer
running. MenuBarAgent remained PID 59001, launched at 11:57:23; no new Ice,
MenuBarAgent, assessment-probe or dynamic-probe crash report was found. The
DynamicStatusItemProbe was still running as PID 67234 at that checkpoint and was
left for the main agent's UI cleanup; it was not silently terminated by this
documentation review.

The assertion-specific logs contain no activation/invalidation exception, API
error completion or unintended lifecycle release between ACTIVE and Reveal.
This is **not** a claim that the complete system log was warning-free:
AppIntents/Spotlight service-connection errors appeared at startup, and AppKit
negative-view-geometry faults appeared at 15:41:10, before activation, then
recurred during later UI states. These are recorded separately; this test did
not establish them as causes of the assertion's behavioral failure.

Reveal was requested before the 45-second watchdog deadline, and the probe then
quit. The watchdog's actual timeout behavior was therefore not accepted by this
run. No further stress, configuration expansion or native-click workaround was
attempted after the failure. The experiment also does not identify the cause of
the four earlier MenuBarAgent crashes.

## Evidence files

All four captures are menu-bar-only images (3456×80 physical pixels), not
Notification Center content captures:

- `/tmp/ice-consolidated.UDfQfH/assessment-baseline.png`
- `/tmp/ice-consolidated.UDfQfH/assessment-active.png`
- `/tmp/ice-consolidated.UDfQfH/assessment-revealed.png`
- `/tmp/ice-consolidated.UDfQfH/1326-clock-return.png`

Unified-log messages for `NativeAssessmentVisibilityProbe` PID 67478 provide
the generation/state timestamps above. Temporary evidence paths may be cleaned
by the system later.
