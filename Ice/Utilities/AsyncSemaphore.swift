//
//  AsyncSemaphore.swift
//  Ice
//

import os.lock

/// A FIFO counting semaphore that suspends tasks without blocking a thread.
///
/// Cancellation and signaling compete while holding the same lock. This makes
/// exactly one of them responsible for resuming a queued continuation and keeps
/// the permit count unchanged when a queued wait is cancelled.
final class AsyncSemaphore: @unchecked Sendable {
    private enum WaiterState {
        case pending
        case waiting
        case signaled
        case cancelled
    }

    private enum WaiterContinuation {
        case none
        case nonThrowing(CheckedContinuation<Void, Never>)
        case throwing(CheckedContinuation<Void, any Error>)
    }

    private final class Waiter: @unchecked Sendable {
        var state = WaiterState.pending
        var continuation = WaiterContinuation.none
    }

    private struct Storage {
        var availablePermits: Int
        var waiters = [Waiter]()
    }

    private enum ResumeAction {
        case none
        case succeed(CheckedContinuation<Void, any Error>)
        case succeedNonThrowing(CheckedContinuation<Void, Never>)
        case cancel(CheckedContinuation<Void, any Error>)

        func perform() {
            switch self {
            case .none:
                break
            case let .succeed(continuation):
                continuation.resume()
            case let .succeedNonThrowing(continuation):
                continuation.resume()
            case let .cancel(continuation):
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    private let storage: OSAllocatedUnfairLock<Storage>

    /// Creates a semaphore with the specified number of available permits.
    init(value: Int) {
        precondition(value >= 0, "AsyncSemaphore requires a nonnegative value")
        storage = OSAllocatedUnfairLock(initialState: Storage(availablePermits: value))
    }

    /// Waits for and consumes a permit, ignoring task cancellation.
    func wait() async {
        let waiter = Waiter()

        await withCheckedContinuation { continuation in
            let action = storage.withLock { storage -> ResumeAction in
                if storage.availablePermits > 0 {
                    storage.availablePermits -= 1
                    waiter.state = .signaled
                    return .succeedNonThrowing(continuation)
                }

                waiter.state = .waiting
                waiter.continuation = .nonThrowing(continuation)
                storage.waiters.append(waiter)
                return .none
            }

            action.perform()
        }
    }

    /// Waits for and consumes a permit, or throws if cancellation wins first.
    func waitUnlessCancelled() async throws {
        let waiter = Waiter()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let action = storage.withLock { storage -> ResumeAction in
                    // `onCancel` can run before this continuation is registered.
                    // Checking the task as well guarantees that an already
                    // cancelled task never consumes an available permit.
                    guard waiter.state != .cancelled, !Task.isCancelled else {
                        waiter.state = .cancelled
                        return .cancel(continuation)
                    }

                    if storage.availablePermits > 0 {
                        storage.availablePermits -= 1
                        waiter.state = .signaled
                        return .succeed(continuation)
                    }

                    waiter.state = .waiting
                    waiter.continuation = .throwing(continuation)
                    storage.waiters.append(waiter)
                    return .none
                }

                action.perform()
            }
        } onCancel: {
            cancel(waiter)
        }
    }

    /// Adds a permit, transferring it directly to the oldest waiter if any.
    ///
    /// - Returns: `true` when a waiter was resumed, otherwise `false`.
    @discardableResult
    func signal() -> Bool {
        let action = storage.withLock { storage -> ResumeAction in
            guard !storage.waiters.isEmpty else {
                storage.availablePermits += 1
                return .none
            }

            let waiter = storage.waiters.removeFirst()
            precondition(waiter.state == .waiting)
            waiter.state = .signaled

            switch waiter.continuation {
            case .none:
                preconditionFailure("A queued semaphore waiter has no continuation")
            case let .nonThrowing(continuation):
                waiter.continuation = .none
                return .succeedNonThrowing(continuation)
            case let .throwing(continuation):
                waiter.continuation = .none
                return .succeed(continuation)
            }
        }

        action.perform()
        if case .none = action {
            return false
        }
        return true
    }

    private func cancel(_ waiter: Waiter) {
        let action = storage.withLock { storage -> ResumeAction in
            switch waiter.state {
            case .pending:
                // The operation closure will observe this state and resume its
                // continuation once it has been created.
                waiter.state = .cancelled
                return .none

            case .waiting:
                guard let index = storage.waiters.firstIndex(where: { $0 === waiter }) else {
                    preconditionFailure("A waiting semaphore task is missing from the queue")
                }
                storage.waiters.remove(at: index)
                waiter.state = .cancelled

                guard case let .throwing(continuation) = waiter.continuation else {
                    preconditionFailure("A cancellable semaphore waiter has no continuation")
                }
                waiter.continuation = .none
                return .cancel(continuation)

            case .signaled, .cancelled:
                // A signal or an earlier cancellation already won the race.
                return .none
            }
        }

        action.perform()
    }
}
