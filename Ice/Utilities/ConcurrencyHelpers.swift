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
