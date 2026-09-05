# Direct native Command-drag follow-up

This is the historical build 1307 record. The
[subsequent review](review-2026-09-05.md) describes the expanded blank-slot fix,
installed build 1311 and the controlled follow-up crash investigation. Its
current implementation supersedes the narrow-blank policy described below.

## Required behavior

Outside Layout, the visible Ice arrow is the only user-facing boundary:

1. Expand Ice, Command-drag a hidden item from its left to its right, and hide
   again: the moved item must remain visible.
2. Expand Ice, Command-drag a visible item to its left, and hide again: the moved
   item must be concealed. This also applies to the first item in Hidden and to
   a drop immediately beside the arrow, not just past an invisible spacer.

## Cause and change

Build 1306 removed the native blank boundary when expanded. Restoring it could
restore an obsolete order after a manual drag. It repaired adjacency only when
entering Layout, and hiding also depended on cached Hidden membership.
Before this build's installation, a live read outside Layout showed Ice at
x=1341 and the blank at x=1375: the blank was on the wrong side.

Build `0.12.0-macos27.108 (1307)` keeps the blank narrow when expanded. Before
concealing it reads the current native order, repairs only the blank-to-Ice
adjacency if necessary, and publishes current section membership before widening
the blank. No other application is moved by this preflight. The only exception
to the Layout-only native drag guard is exactly Ice's hidden boundary moving
left of Ice's own visible control. Other buttons have no proxy or input monitor.

Mouse-up triggers Ice's normal action so the user's physical press has finished
before a boundary correction. A newer expand request cancels pending hiding.
Failure to verify the boundary leaves the bar expanded. Off-bar/coincident AX
frames cannot reassign items. A real right-hand item can be reclassified Visible
even while left-hand items are concealed.

## Installed evidence

- Release arm64 build succeeded. Scoped SwiftLint and `git diff --check` passed.
- All 12 `NativeMenuBarBoundaryTests` assertions passed, covering both directions,
  first-hidden-item classification, overlapping hit areas, overflow/coincident
  frames, a drop inside the Ice/blank pair, wrong-side and missing boundaries.
  These are decision tests, not a claim of physical gesture acceptance.
- Installed `/Applications/Ice.app`: `.108 (1307)`, strict/deep ad-hoc signature
  verified with the unchanged designated bundle-identifier requirement.
- Launched from General, not Layout. The previously wrong pair became blank
  x=1349 and Ice x=1358; hiding left the Ice arrow and native system controls
  visible. No Layout repair was needed to reach that state.
- Native Ice activation expanded the two third-party items. The same blank
  remained at x=1349, now width 3, immediately left of Ice. App Volumes x=1273,
  Macs Fan Control x=1311 and Ice x=1358 agreed with the intended expanded order.
- Read-only audit: zero Ice-owned event taps. No Keychain, TCC, system security
  setting or other application's position preference was changed.
- Previous installed build preserved at
  `/tmp/ice-native-boundary.EQlHmp/previous-build-1306.app`.

## User acceptance and regression checks

The user physically tested the two requested directions on installed build 1307
and explicitly replied that both were normal. This is the direct native-gesture
acceptance evidence, not a substitute Layout test. The computer-use API itself
cannot hold Command through a drag.

The user separately confirmed that clicking the clock opened Notification Center
and left Ice hidden. Automated AX clock activation was inconclusive after the
system menu-bar process changed; coordinate activation returned
`noWindowsAvailable`. The native click result is therefore user-confirmed, not
an automated pass.

Ten automated native Ice activations alternated Forward/Back with one Ice control
in 7.8 seconds and finished hidden as they started. This is state-level evidence,
not frame-level flicker acceptance. No user's item order was intentionally reset.

## Open stability finding — not a stable-release acceptance

A final diagnostic audit found four MenuBarAgent crash reports during the manual
test interval: `MenuBarAgent-2026-09-05-115644.ips`, `-115651.ips`, `-115704.ips`,
and `-115724.ips` in `~/Library/Logs/DiagnosticReports`. The last process was
automatically replaced by PID 59001 at 11:57:23; Ice remained PID 58905.
Ice does not restart MenuBarAgent, and no restart command was issued by QA.

The first crash's unified log at 11:56:42.248 identifies
`MenuBarCore/WorkspaceController.swift:522`: a fatal infinite-update guard after
1000 updates, with two pending `WorkspaceUpdate.input` entries. The crash stack
is an assertion failure on the system agent's main event thread. This establishes
an input-update loop in the system process, but does not establish whether a
manual drag, Ice's own boundary correction or another input interaction caused
it. Do not dismiss it as unrelated or claim it has been fixed.

No later MenuBarAgent crash report was found in the audit after the subsequent
ten-toggle check. That does not establish long-term stability. The two requested
flows and native Notification Center are user-accepted; this separate stability
finding remains open and requires a controlled reproduction before another
implementation change.

Build log and diagnostic captures are under `/tmp/ice-native-boundary.EQlHmp`.
An isolated temporary wide-glyph probe again put its oversized control in native
overflow (AX y=1121); it was not adopted, and the probe process was terminated.
No commit or push was performed for this follow-up.
