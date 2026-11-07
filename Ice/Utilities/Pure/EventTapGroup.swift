//
//  EventTapGroup.swift
//  Ice
//

import Foundation

/// The repetition counter shared by the callbacks of one event operation.
///
/// It is separate from ``EventTapGroup`` on purpose: the callbacks capture only
/// the counter, never the group that owns the taps, so there is no
/// group -> tap -> callback -> group reference cycle.
final class EventCounter: @unchecked Sendable {
    // @unchecked Sendable: the taps run on the main run loop, the only place that mutates `count`.
    var count: Int

    init(count: Int) {
        self.count = count
    }
}

/// Owns the event taps of one operation until it ends.
final class EventTapGroup<Tap: AnyObject>: @unchecked Sendable {
    // @unchecked Sendable: adopted once during setup and torn down once at the end, on the main actor.
    private var taps = [Tap]()
    private let disable: (Tap) -> Void

    /// - Parameter disable: Turns a tap off (stops its event delivery).
    init(disable: @escaping (Tap) -> Void) {
        self.disable = disable
    }

    /// Keeps the taps alive until ``tearDown()``.
    func adopt(_ taps: [Tap]) {
        self.taps.append(contentsOf: taps)
    }

    /// Releases the taps. Idempotent.
    func tearDown() {
        let owned = taps
        taps.removeAll()
        for tap in owned {
            disable(tap)
        }
    }

    deinit {
        tearDown()
    }
}
