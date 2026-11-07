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
///
/// Everything that touches the taps (adopting, disabling, releasing) is
/// isolated to the main actor: the callbacks run on the main run loop, so the
/// taps must not be turned off or freed from another thread.
@MainActor
final class EventTapGroup<Tap: AnyObject> {
    // Read from the (nonisolated) deinit only to find out whether cleanup was missed.
    private nonisolated(unsafe) var taps = [Tap]()
    private let disable: @MainActor (Tap) -> Void

    /// - Parameter disable: Turns a tap off (stops its event delivery).
    nonisolated init(disable: @escaping @MainActor (Tap) -> Void) {
        self.disable = disable
    }

    /// Keeps the taps alive until ``tearDown()``.
    func adopt(_ taps: [Tap]) {
        self.taps.append(contentsOf: taps)
    }

    /// Disables and releases the taps. Idempotent.
    func tearDown() {
        let owned = taps
        taps.removeAll()
        for tap in owned {
            disable(tap)
        }
    }

    /// Runs `body` with a new group and tears the group down, on the main
    /// actor, when `body` returns, throws or is cancelled. Callers `await` the
    /// whole call, so the cleanup has finished when it returns.
    static func withGroup<R: Sendable>(
        disable: @escaping @MainActor (Tap) -> Void,
        body: @MainActor (EventTapGroup<Tap>) async throws -> R
    ) async rethrows -> R {
        let group = EventTapGroup<Tap>(disable: disable)
        defer { group.tearDown() }
        return try await body(group)
    }

    // A deinit can't do main-actor work. If a group was dropped without
    // `tearDown()` (a bug), still turn the taps off, on the main actor.
    deinit {
        guard !taps.isEmpty else {
            return
        }
        assertionFailure("EventTapGroup deallocated without tearDown()")
        nonisolated(unsafe) let leftover = taps
        let disable = self.disable
        Task { @MainActor in
            leftover.forEach(disable)
        }
    }
}
