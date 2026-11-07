//
//  PendingPIDTracker.swift
//  Ice
//

/// Tracks menu bar item windows whose source process could not be resolved,
/// and decides when a new lookup is worth trying.
///
/// A failed lookup is retried after a backoff delay, even when the set of
/// window identifiers never changes, without invalidating the whole item
/// cache. Only the pending windows are looked at again. The clock is
/// injected (`now`, in seconds) so the policy is testable.
struct PendingPIDTracker<ID: Hashable> {
    private struct Entry {
        var failures: Int
        var retryAt: Double
    }

    /// Delay before retry number `n` (index `n - 1`); the last value is the cap.
    private let delays: [Double]
    private var entries = [ID: Entry]()

    init(delays: [Double] = [30, 60, 120, 300]) {
        precondition(!delays.isEmpty)
        self.delays = delays
    }

    /// Records a failed lookup and schedules the next one.
    ///
    /// A failure reported while the previous retry is not yet due (for
    /// example during an unrelated re-cache) does not escalate the backoff.
    mutating func recordFailure(_ id: ID, now: Double) {
        if let entry = entries[id], entry.retryAt > now {
            return
        }
        let failures = (entries[id]?.failures ?? 0) + 1
        let delay = delays[min(failures, delays.count) - 1]
        entries[id] = Entry(failures: failures, retryAt: now + delay)
    }

    /// Records that the window's source process was resolved.
    mutating func recordSuccess(_ id: ID) {
        entries.removeValue(forKey: id)
    }

    /// The running applications changed: every pending lookup may succeed now.
    ///
    /// Policy: retry immediately and restart the backoff from the first
    /// delay, so a new failure waits 30 s (not the old, longer delay).
    mutating func appsChanged() {
        for id in entries.keys {
            entries[id] = Entry(failures: 0, retryAt: -.infinity)
        }
    }

    /// Forgets windows that are no longer on screen.
    mutating func prune(keeping ids: some Collection<ID>) {
        let keep = Set(ids)
        entries = entries.filter { keep.contains($0.key) }
    }

    /// Returns whether any pending window among `ids` is due for a retry.
    func isRetryDue(among ids: some Collection<ID>, now: Double) -> Bool {
        ids.contains { id in
            entries[id].map { $0.retryAt <= now } ?? false
        }
    }
}
