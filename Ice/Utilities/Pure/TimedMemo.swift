//
//  TimedMemo.swift
//  Ice
//

/// Remembers one computed value for a short time.
///
/// Used to keep expensive lookups (window lists, Accessibility queries) out
/// of per-event code such as mouse tracking: many events within `ttl` share
/// one computation. The clock is passed in (`now`, in seconds) for testing.
struct TimedMemo<Value> {
    private let ttl: Double
    private var stored: (value: Value, date: Double)?

    init(ttl: Double) {
        self.ttl = ttl
    }

    /// Returns the remembered value, computing a new one when there is none,
    /// when it is older than the TTL, or when the clock went backwards.
    mutating func value(now: Double, compute: () -> Value) -> Value {
        if let stored, now >= stored.date, now - stored.date < ttl {
            return stored.value
        }
        let value = compute()
        stored = (value, now)
        return value
    }

    /// Forgets the value, so the next call computes a new one.
    mutating func invalidate() {
        stored = nil
    }
}
