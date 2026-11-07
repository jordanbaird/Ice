//
//  SectionSession.swift
//  Ice
//

/// The lifecycle of one section's show-to-hide cycle: which display it is
/// pinned to, whether it is still active, and when the rehide checks may be
/// armed or must be torn down.
///
/// Every arm/disarm of the rehide checks and every hide caused by a display
/// change goes through this type (`MenuBarSection` is only glue), so the
/// ordering rules live in one tested place.
final class SectionSession {
    struct Effects {
        var armRehide: () -> Void
        var disarmRehide: () -> Void
        var hideSection: () -> Void
    }

    private let effects: Effects
    private var target = TargetDisplaySession()

    private(set) var generation: UInt64 = 0
    private(set) var isActive = false
    private(set) var isRehideArmed = false

    init(effects: Effects) {
        self.effects = effects
    }

    var pinnedDisplayID: UInt32? {
        target.pinnedDisplayID
    }

    /// Starts a cycle pinned to the display `resolve` returns now. Any earlier
    /// cycle (and the tokens it handed out) stops being current.
    @discardableResult
    func begin(resolveDisplay resolve: () -> UInt32) -> UInt64 {
        generation += 1
        isActive = true
        _ = target.begin(resolve: resolve)
        return generation
    }

    /// The display for the rehide checks (see ``TargetDisplaySession``).
    func displayID(connected: Set<UInt32>, resolve: () -> UInt32) -> UInt32? {
        target.displayID(connected: connected, resolve: resolve)
    }

    /// Arms the rehide checks, but only if `token` is still the active cycle.
    /// A show that was suspended (waiting for the bar's cache) and finished
    /// after the section was hidden or its display removed must not arm them.
    @discardableResult
    func armRehideIfCurrent(_ token: UInt64) -> Bool {
        guard isActive, token == generation else {
            return false
        }
        isRehideArmed = true
        effects.armRehide()
        return true
    }

    /// Re-arms the checks from the rehide timer, if the cycle is still active.
    func rearmIfActive() {
        guard isActive else {
            return
        }
        isRehideArmed = true
        effects.armRehide()
    }

    /// Ends the cycle (the section was hidden). Idempotent.
    func end() {
        generation += 1
        isActive = false
        target.end()
        isRehideArmed = false
        effects.disarmRehide()
    }

    /// Call when the connected displays change. If this cycle's display is
    /// gone, the cycle ends and the section is hidden, whether it is shown
    /// inline or in the bar, and whether or not a rehide timer was armed.
    func reconcile(connectedDisplayIDs: Set<UInt32>) {
        guard isActive, let pinned = target.pinnedDisplayID, !connectedDisplayIDs.contains(pinned) else {
            return
        }
        end()
        effects.hideSection()
    }
}
