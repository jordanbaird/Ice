//
//  MotionPolicy.swift
//  Ice
//

/// Durations for the app's transitions: 150 to 300 ms, and none at all when the
/// user turned on "Reduce motion" in Accessibility settings.
enum MotionPolicy {
    static let minimum = 0.15
    static let maximum = 0.30

    enum Kind: CaseIterable {
        /// A fade of a whole panel (appearance overlay).
        case fade
        /// Rearranging views (layout editor).
        case reorder
        /// A color change.
        case color
    }

    static func duration(base: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : min(max(base, minimum), maximum)
    }

    static func duration(for kind: Kind, reduceMotion: Bool) -> Double {
        switch kind {
        case .fade: duration(base: 0.2, reduceMotion: reduceMotion)
        case .reorder: duration(base: 0.2, reduceMotion: reduceMotion)
        case .color: duration(base: 0.15, reduceMotion: reduceMotion)
        }
    }
}
