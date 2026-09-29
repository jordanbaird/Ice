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

/// Delivers the first result of a race between an operation and its
/// timeout, exactly once, whichever way round the two arrive.
private final class TimeoutRace<Success: Sendable>: Sendable {
    private enum State: Sendable {
        case waiting
        case installed(CheckedContinuation<Success, any Error>)
        case finished(Result<Success, any Error>)
        case done
    }

    private let state = OSAllocatedUnfairLock(initialState: State.waiting)

    /// Installs the continuation to resume, resuming it at once if the
    /// race has already finished.
    func install(_ continuation: CheckedContinuation<Success, any Error>) {
        let result: Result<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting:
                state = .installed(continuation)
                return nil
            case .finished(let result):
                state = .done
                return result
            case .installed, .done:
                return nil
            }
        }
        if let result {
            continuation.resume(with: result)
        }
    }

    /// Finishes the race with the given result, unless it has already
    /// finished.
    func finish(with result: Result<Success, any Error>) {
        let continuation: CheckedContinuation<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting:
                state = .finished(result)
                return nil
            case .installed(let continuation):
                state = .done
                return continuation
            case .finished, .done:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}

extension Task {
    /// Runs the given throwing operation asynchronously alongside a
    /// timeout operation.
    ///
    /// If the operation does not complete within the provided
    /// duration, the operation is cancelled and a ``TaskTimeoutError``
    /// is thrown at once, without waiting for the operation to finish.
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
        // Unstructured tasks, not a task group: leaving a group waits for
        // every child, so an operation that ignored cancellation held the
        // caller past the timeout for as long as it ran.
        let race = TimeoutRace<Success>()
        let operationTask = _Concurrency.Task<Success, any Error>(operation: operation)
        let timeoutTask = _Concurrency.Task<Void, Never> {
            do {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
            } catch {
                return // Cancelled, as the operation finished first.
            }
            operationTask.cancel()
            race.finish(with: .failure(TaskTimeoutError()))
        }
        _Concurrency.Task<Void, Never> {
            let result = await operationTask.result
            timeoutTask.cancel()
            race.finish(with: result)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
            }
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            race.finish(with: .failure(_Concurrency.CancellationError()))
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
