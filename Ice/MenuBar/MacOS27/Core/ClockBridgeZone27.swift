//
//  ClockBridgeZone27.swift
//  Ice
//

import CoreGraphics

/// Decides whether a click must be let through to a system item.
///
/// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on
/// the clock (measured on macOS 27.0), so such clicks lift the assertion first.
enum ClockBridgeZone27 {
    static func shouldBridge(click: CGPoint, systemItemFrames: [CGRect], isConcealing: Bool) -> Bool {
        guard isConcealing else {
            return false
        }
        return systemItemFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(click) }
    }
}
