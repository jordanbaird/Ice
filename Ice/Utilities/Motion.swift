//
//  Motion.swift
//  Ice
//

import AppKit
import SwiftUI

/// Applies ``MotionPolicy`` with the system's "Reduce motion" setting.
enum Motion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func duration(_ kind: MotionPolicy.Kind) -> TimeInterval {
        MotionPolicy.duration(for: kind, reduceMotion: reduceMotion)
    }

    /// A SwiftUI animation for the kind, or `nil` (no animation) with reduced motion.
    static func animation(_ kind: MotionPolicy.Kind) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration(kind))
    }

    /// Runs `changes` inside an AppKit animation group with the kind's duration
    /// (zero with reduced motion).
    @MainActor
    static func animate(_ kind: MotionPolicy.Kind, _ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration(kind)
            context.allowsImplicitAnimation = true
            changes()
        }
    }
}
