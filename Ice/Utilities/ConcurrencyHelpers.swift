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

// MARK: - CancellingContinuation

struct CancellingContinuation<T>: Sendable {
    private enum State: @unchecked Sendable {
        case initial
        case willCancel
        case willResume(Result<T, any Error>)
        case awaiting(CheckedContinuation<T, any Error>)
        case cancelled
        case resumed

        mutating func set(_ continuation: CheckedContinuation<T, any Error>, function: String) {
            switch self {
            case .initial:
                self = .awaiting(continuation)
            case .willCancel:
                continuation.resume(throwing: CancellationError())
                self = .cancelled
            case .willResume(let result):
                continuation.resume(with: result)
                self = .resumed
            case .awaiting, .cancelled, .resumed:
                fatalError("SWIFT TASK CONTINUATION MISUSE: \(function) tried to await its continuation more than once.")
            }
        }

        mutating func cancel() {
            switch self {
            case .initial, .willCancel, .willResume:
                self = .willCancel
            case .awaiting(let continuation):
                continuation.resume(throwing: CancellationError())
                self = .cancelled
            case .cancelled, .resumed:
                break // Ignore.
            }
        }

        mutating func resume(result: sending Result<T, any Error>, function: String) {
            switch self {
            case .initial:
                self = .willResume(result)
            case .willCancel, .cancelled:
                break // Ignore.
            case .willResume, .resumed:
                fatalError("SWIFT TASK CONTINUATION MISUSE: \(function) tried to resume its continuation more than once.")
            case .awaiting(let continuation):
                continuation.resume(with: result)
                self = .resumed
            }
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State.initial)
    private let function: String

    fileprivate init(function: String) {
        self.function = function
    }

    func resume(with result: sending Result<T, any Error>) {
        state.withLock { [result] in $0.resume(result: result, function: function) }
    }

    func resume(returning value: sending T) {
        resume(with: .success(value))
    }

    func resume(throwing error: any Error) {
        resume(with: .failure(error))
    }

    func resume() where T == Void {
        resume(returning: ())
    }

    func cancel() {
        state.withLock { $0.cancel() }
    }

    fileprivate func wait(
        isolation: isolated (any Actor)? = #isolation,
        body: (CancellingContinuation<T>) -> Void,
        onCancel: (CancellingContinuation<T>) -> Void
    ) async throws -> sending T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(function: function) { continuation in
                state.withLock { $0.set(continuation, function: function) }
                body(self)
            }
        } onCancel: {
            onCancel(self)
        }
    }
}

func withCancellingContinuation<T>(
    isolation: isolated (any Actor)? = #isolation,
    function: String = #function,
    body: (_ continuation: CancellingContinuation<T>) -> Void,
    onCancel: (_ continuation: CancellingContinuation<T>) -> Void
) async throws -> sending T {
    let continuation = CancellingContinuation<T>(function: function)
    return try await continuation.wait(body: body, onCancel: onCancel)
}
