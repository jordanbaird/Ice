//
//  SignalWait.swift
//  Ice
//

import Foundation

/// Waits for an external completion signal (for example the return event of a
/// menu bar item move) with a timeout.
///
/// The wait ends in exactly one of three ways, and the underlying continuation
/// is resumed exactly once whichever comes first:
/// - the signal arrives (`complete(.success(()))` or `.failure`),
/// - the timeout expires (``TaskTimeoutError``),
/// - the calling task is cancelled (`CancellationError`).
///
/// Cancellation is observed by a handler wrapped around the continuation
/// itself, so cancelling the caller (or an expiring timeout) always unblocks
/// the wait; the caller's `defer`/``EventTapGroup/withGroup`` cleanup then runs.
enum SignalWait {
    typealias Completion = @Sendable (Result<Void, any Error>) -> Void

    /// Resumes a continuation at most once, even if the result arrives before
    /// the continuation is installed (for example when already cancelled).
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?
        private var result: Result<Void, any Error>?

        func install(_ continuation: CheckedContinuation<Void, any Error>) {
            let early = lock.withLock { () -> Result<Void, any Error>? in
                if let result {
                    return result
                }
                self.continuation = continuation
                return nil
            }
            if let early {
                continuation.resume(with: early)
            }
        }

        func finish(_ newResult: Result<Void, any Error>) {
            let toResume = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                guard result == nil else {
                    return nil          // first outcome wins; later ones are ignored
                }
                result = newResult
                defer { continuation = nil }
                return continuation
            }
            toResume?.resume(with: newResult)
        }
    }

    /// - Parameters:
    ///   - timeout: How long to wait for the signal.
    ///   - start: Starts the operation, on the main actor, and hands over the
    ///     completion callback the signal must call.
    @MainActor
    static func wait(
        timeout: Duration,
        start: @MainActor (_ complete: @escaping Completion) -> Void
    ) async throws {
        let gate = Gate()
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return                  // cancelled because the wait already ended
            }
            gate.finish(.failure(TaskTimeoutError()))
        }
        defer { timer.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                gate.install(continuation)
                start { gate.finish($0) }
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}
