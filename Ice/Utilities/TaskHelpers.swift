//
//  TaskHelpers.swift
//  Ice
//

import Foundation

// MARK: - Task Timeout

extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a new
    /// top-level task on behalf of the current actor.
    ///
    /// - Parameters:
    ///   - timeout: The amount of time to wait before cancelling the task
    ///     by throwing a ``TaskTimeoutError``.
    ///   - tolerance: The tolerance of the clock.
    ///   - clock: The clock that manages the timeout operation.
    ///   - priority: The priority of the task.
    ///   - operation: The operation to perform.
    @discardableResult
    init<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = ContinuousClock(),
        priority: TaskPriority? = nil,
        @_inheritActorContext @_implicitSelfCapture
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) {
        self.init(priority: priority) {
            try await Task.run(operation: operation, withTimeout: timeout, tolerance: tolerance, clock: clock)
        }
    }

    /// Runs the given throwing operation asynchronously as part of a new
    /// top-level task.
    ///
    /// - Parameters:
    ///   - timeout: The amount of time to wait before cancelling the task
    ///     by throwing a ``TaskTimeoutError``.
    ///   - tolerance: The tolerance of the clock.
    ///   - clock: The clock that manages the timeout operation.
    ///   - priority: The priority of the task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    @discardableResult
    static func detached<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = ContinuousClock(),
        priority: TaskPriority? = nil,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) -> Task<Success, Failure> {
        detached(priority: priority) {
            try await run(operation: operation, withTimeout: timeout, tolerance: tolerance, clock: clock)
        }
    }

    private static func run<C: Clock>(
        operation: sending @escaping @isolated(any) () async throws -> Success,
        withTimeout timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration?,
        clock: C
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask(operation: operation)
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

// MARK: TaskTimeoutError

/// An error that indicates that a task timed out.
struct TaskTimeoutError: LocalizedError, CustomStringConvertible {
    let description = "Task timed out before completion"
    var errorDescription: String? { description }
}
