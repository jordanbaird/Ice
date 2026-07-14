//
//  ConcurrencyHelpers.swift
//  Ice
//

import Foundation
import os.lock

// MARK: - Task Timeout

/// An error that indicates that a task timed out.
struct TaskTimeoutError: CustomStringConvertible, LocalizedError {
    let description = "Task timed out before completion"
    var errorDescription: String? { description }
}

extension Task {
    /// Runs the given throwing operation asynchronously alongside a
    /// timeout operation in a structured task group.
    ///
    /// If the operation does not complete within the provided
    /// duration, the timeout operation cancels the group and throws
    /// a ``TaskTimeoutError``.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result of the operation, if successful.
    private static func withTimeout<C: Clock>(
        _ timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration?,
        clock: C,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
                throw TaskTimeoutError()
            }
            guard let success = try await group.next() else {
                throw _Concurrency.CancellationError()
            }
            group.cancelAll()
            return success
        }
    }
}

extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    @discardableResult
    init<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        @_inheritActorContext @_implicitSelfCapture
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) {
        self.init(name: name, priority: priority) {
            try await Task.withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }

    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ _detached_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    @discardableResult
    static func detached<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) -> Task<Success, Failure> {
        detached(name: name, priority: priority) {
            try await withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }
}

// MARK: - One-Shot Operations

/// Coordinates a resource-backed async operation that can either finish or
/// be cancelled exactly once.
///
/// The resource is started only while the operation is pending. Whichever of
/// ``finish()`` and ``cancel()`` wins stops the resource before resuming the
/// suspended waiter. This also handles cancellation racing with `start(with:)`.
final class OneShotOperation<Resource>: @unchecked Sendable {
    private enum Outcome: Sendable {
        case finished
        case cancelled
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case starting
        case started
        case stopped
    }

    private struct ResourceBox: @unchecked Sendable {
        let value: Resource
    }

    private struct Delivery: Sendable {
        let continuation: CheckedContinuation<Void, any Error>
        let outcome: Outcome
    }

    private struct Finalization: Sendable {
        var resource: ResourceBox? = nil
        var delivery: Delivery? = nil
    }

    private struct State: Sendable {
        var phase = Phase.idle
        var resource: ResourceBox?
        var outcome: Outcome?
        var continuation: CheckedContinuation<Void, any Error>?
        var hasWaiter = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let startResource: (Resource) -> Void
    private let stopResource: (Resource) -> Void

    /// Creates an operation with actions that start and stop its resource.
    init(
        start: @escaping (Resource) -> Void,
        stop: @escaping (Resource) -> Void
    ) {
        self.startResource = start
        self.stopResource = stop
    }

    /// Starts the resource if neither completion nor cancellation has won.
    @discardableResult
    func start(with resource: Resource) -> Bool {
        let resourceBox = ResourceBox(value: resource)
        let shouldStart = state.withLock { state in
            guard state.phase == .idle, state.outcome == nil else {
                return false
            }
            state.phase = .starting
            state.resource = resourceBox
            return true
        }
        guard shouldStart else {
            return false
        }

        startResource(resource)

        let finalization = state.withLock { state -> Finalization in
            precondition(state.phase == .starting)
            if let outcome = state.outcome {
                state.phase = .stopped
                let resource = state.resource
                state.resource = nil
                if let continuation = state.continuation {
                    state.continuation = nil
                    return Finalization(
                        resource: resource,
                        delivery: Delivery(continuation: continuation, outcome: outcome)
                    )
                }
                return Finalization(resource: resource)
            } else {
                state.phase = .started
                return Finalization()
            }
        }
        perform(finalization)
        return true
    }

    /// Suspends until the operation finishes or is cancelled.
    ///
    /// An operation supports exactly one waiter.
    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let immediateOutcome = state.withLock { state -> Outcome? in
                precondition(!state.hasWaiter, "OneShotOperation only supports one waiter")
                state.hasWaiter = true
                if let outcome = state.outcome, state.phase != .starting {
                    return outcome
                } else {
                    state.continuation = continuation
                    return nil
                }
            }
            if let immediateOutcome {
                resume(continuation, with: immediateOutcome)
            }
        }
    }

    /// Finishes the operation. Returns `true` only for the winning caller.
    @discardableResult
    func finish() -> Bool {
        resolve(with: .finished)
    }

    /// Cancels the operation. Returns `true` only for the winning caller.
    @discardableResult
    func cancel() -> Bool {
        resolve(with: .cancelled)
    }

    private func resolve(with outcome: Outcome) -> Bool {
        let finalization = state.withLock { state -> Finalization? in
            guard state.outcome == nil else {
                return nil
            }
            state.outcome = outcome

            var resource: ResourceBox?
            switch state.phase {
            case .idle:
                state.phase = .stopped
            case .starting:
                // `start(with:)` performs cleanup after `startResource`
                // returns, then delivers the outcome to any waiter.
                return Finalization()
            case .started:
                state.phase = .stopped
                resource = state.resource
                state.resource = nil
            case .stopped:
                preconditionFailure("Unresolved operation cannot already be stopped")
            }

            if let storedContinuation = state.continuation {
                state.continuation = nil
                return Finalization(
                    resource: resource,
                    delivery: Delivery(continuation: storedContinuation, outcome: outcome)
                )
            }
            return Finalization(resource: resource)
        }
        guard let finalization else {
            return false
        }
        perform(finalization)
        return true
    }

    private func perform(_ finalization: Finalization) {
        if let resource = finalization.resource {
            stopResource(resource.value)
        }
        if let delivery = finalization.delivery {
            resume(delivery.continuation, with: delivery.outcome)
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<Void, any Error>,
        with outcome: Outcome
    ) {
        switch outcome {
        case .finished:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        }
    }
}
