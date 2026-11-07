//
//  BackgroundCaptureCache.swift
//  Ice
//

import Foundation

/// The two ends of a background operation started by ``BackgroundCaptureCache``.
///
/// Swift cancellation is cooperative, so the end of the *result* (a timeout)
/// and the end of the *physical work* are different events:
/// - `deliver` settles the result. Only the first call counts; a timeout
///   delivers `nil` and the UI keeps the previous value.
/// - `finish` reports that the work really ended (or confirmed cancellation).
///   Until then the operation keeps occupying its slot.
struct BackgroundCaptureOperation<Value> {
    let deliver: (Value?) -> Void
    let finish: () -> Void
}

/// A cache for results that are produced slowly and asynchronously (for
/// example screen captures), read from code that must never block.
///
/// `value(for:)` always returns immediately with the last known value (or
/// `nil`). When the value is missing or older than `maxAge`, it starts at
/// most one background operation per key (single flight), and no more than
/// `maxInFlight` overall. Slots are released only by `finish`, so operations
/// that ignore cancellation after a timeout are still counted and cannot pile
/// up. Results that arrive after ``invalidate()`` or after their timeout are
/// discarded, and a failed key is not retried before `maxAge` passes.
final class BackgroundCaptureCache<Key: Hashable, Value>: @unchecked Sendable {
    private struct Entry {
        let value: Value
        let date: TimeInterval
    }

    private let lock = NSLock()
    private let maxInFlight: Int
    private let maxAge: TimeInterval
    private let maxEntries: Int
    private let now: () -> TimeInterval
    private let start: (Key, BackgroundCaptureOperation<Value>) -> Void

    private var entries = [Key: Entry]()
    /// Operations whose physical work has not finished, with their tokens.
    private var running = [Key: UInt64]()
    /// Operations whose result has not been settled yet.
    private var awaitingResult = [Key: UInt64]()
    private var lastFailure = [Key: TimeInterval]()
    private var generation: UInt64 = 0
    private var nextToken: UInt64 = 0

    /// The number of failure cooldowns currently remembered.
    var cooldownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lastFailure.count
    }

    /// - Parameters:
    ///   - maxInFlight: The most operations whose work is still running.
    ///   - maxAge: How long a value is fresh, in seconds.
    ///   - maxEntries: The most values kept; the oldest are dropped.
    ///   - now: The clock, in seconds.
    ///   - start: Starts an operation for a key. It must not block, must call
    ///     `deliver` with the result (or `nil`), and `finish` when the work ends.
    init(
        maxInFlight: Int,
        maxAge: TimeInterval,
        maxEntries: Int = 16,
        now: @escaping () -> TimeInterval,
        start: @escaping (Key, BackgroundCaptureOperation<Value>) -> Void
    ) {
        self.maxInFlight = maxInFlight
        self.maxAge = maxAge
        self.maxEntries = maxEntries
        self.now = now
        self.start = start
    }

    /// Returns the last known value for the key without blocking.
    func value(for key: Key) -> Value? {
        lock.lock()
        let current = now()
        let entry = entries[key]
        let isStale = entry.map { current - $0.date >= maxAge } ?? true
        let isCoolingDown = lastFailure[key].map { current - $0 < maxAge } ?? false
        var token: UInt64?
        if isStale, !isCoolingDown, running[key] == nil, running.count < maxInFlight {
            nextToken += 1
            token = nextToken
            running[key] = nextToken
            awaitingResult[key] = nextToken
        }
        let startedGeneration = generation
        lock.unlock()

        if let token {
            let operation = BackgroundCaptureOperation<Value>(
                deliver: { [weak self] result in
                    self?.deliver(key: key, token: token, generation: startedGeneration, result: result)
                },
                finish: { [weak self] in
                    self?.finish(key: key, token: token)
                }
            )
            start(key, operation)
        }
        return entry?.value
    }

    /// Drops every value and ignores the results of operations in flight.
    /// Their slots stay occupied until they report `finish`.
    func invalidate() {
        lock.lock()
        generation += 1
        entries.removeAll()
        awaitingResult.removeAll()
        lastFailure.removeAll()
        lock.unlock()
    }

    private func deliver(key: Key, token: UInt64, generation startedGeneration: UInt64, result: Value?) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == startedGeneration, awaitingResult[key] == token else {
            return
        }
        awaitingResult.removeValue(forKey: key)
        let current = now()
        guard let result else {
            lastFailure[key] = current
            pruneCooldowns(at: current)
            return
        }
        lastFailure.removeValue(forKey: key)
        entries[key] = Entry(value: result, date: current)
        if entries.count > maxEntries, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    private func finish(key: Key, token: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if running[key] == token {
            running.removeValue(forKey: key)
        }
        // Work that ended without delivering counts as a failure.
        if awaitingResult[key] == token {
            awaitingResult.removeValue(forKey: key)
            lastFailure[key] = now()
        }
    }

    /// Forgets cooldowns that have expired, so abandoned keys don't accumulate.
    private func pruneCooldowns(at current: TimeInterval) {
        lastFailure = lastFailure.filter { current - $0.value < maxAge }
    }
}
