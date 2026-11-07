//
//  BackgroundCaptureCache.swift
//  Ice
//

import Foundation

/// A cache for results that are produced slowly and asynchronously (for
/// example screen captures), read from code that must never block.
///
/// `value(for:)` always returns immediately with the last known value (or
/// `nil`). When the value is missing or older than `maxAge`, it starts at
/// most one background operation per key (single flight), and no more than
/// `maxInFlight` overall. Results that arrive after ``invalidate()`` are
/// discarded, a failed key is not retried before `maxAge` passes, and each operation can complete only once, so a timeout and
/// the late real result cannot both be applied.
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
    private let start: (Key, @escaping (Value?) -> Void) -> Void

    private var entries = [Key: Entry]()
    private var inFlight = [Key: UInt64]()
    private var lastFailure = [Key: TimeInterval]()
    private var generation: UInt64 = 0
    private var nextToken: UInt64 = 0

    /// - Parameters:
    ///   - maxInFlight: The most operations running at once.
    ///   - maxAge: How long a value is fresh, in seconds.
    ///   - maxEntries: The most values kept; the oldest are dropped.
    ///   - now: The clock, in seconds.
    ///   - start: Starts an operation for a key and calls the completion
    ///     handler with its result (`nil` on failure). It must not block.
    init(
        maxInFlight: Int,
        maxAge: TimeInterval,
        maxEntries: Int = 16,
        now: @escaping () -> TimeInterval,
        start: @escaping (Key, @escaping (Value?) -> Void) -> Void
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
        let entry = entries[key]
        let isStale = entry.map { now() - $0.date >= maxAge } ?? true
        let isCoolingDown = lastFailure[key].map { now() - $0 < maxAge } ?? false
        var token: UInt64?
        if isStale, !isCoolingDown, inFlight[key] == nil, inFlight.count < maxInFlight {
            nextToken += 1
            token = nextToken
            inFlight[key] = nextToken
        }
        let startedGeneration = generation
        lock.unlock()

        if let token {
            start(key) { [weak self] result in
                self?.complete(key: key, token: token, generation: startedGeneration, result: result)
            }
        }
        return entry?.value
    }

    /// Drops every value and ignores the results of operations in flight.
    func invalidate() {
        lock.lock()
        generation += 1
        entries.removeAll()
        inFlight.removeAll()
        lastFailure.removeAll()
        lock.unlock()
    }

    private func complete(key: Key, token: UInt64, generation startedGeneration: UInt64, result: Value?) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == startedGeneration, inFlight[key] == token else {
            return
        }
        inFlight.removeValue(forKey: key)
        guard let result else {
            lastFailure[key] = now()
            return
        }
        lastFailure.removeValue(forKey: key)
        entries[key] = Entry(value: result, date: now())
        if entries.count > maxEntries, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries.removeValue(forKey: oldest)
        }
    }
}
