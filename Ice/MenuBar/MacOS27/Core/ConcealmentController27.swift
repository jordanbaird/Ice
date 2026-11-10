//
//  ConcealmentController27.swift
//  Ice
//

import Foundation
import OSLog

/// A live assessment-mode assertion.
protocol ConcealmentToken27: AnyObject {}

/// Activates and releases assessment-mode assertions.
///
/// The app implements it with the private `MenuBarClientCore` API; tests use a fake.
@MainActor
protocol ConcealmentBackend27: AnyObject {
    /// Activates an assertion that keeps only the given applications' items on the bar.
    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27

    /// Releases an assertion.
    func invalidate(_ token: ConcealmentToken27)
}

/// Keeps the live assertions in step with a target.
///
/// Every transition activates the new assertions before releasing the old
/// ones. Because assertions combine as a union of allowlists, an application
/// concealed both before and after a transition stays concealed throughout.
///
/// Callers must not overlap calls to `apply(target:running:)`.
@MainActor
final class ConcealmentController27 {
    private struct Spec: Equatable {
        let concealed: Set<String>
        let allowlist: [String]
    }

    private struct Live {
        let spec: Spec
        let token: ConcealmentToken27
    }

    private let backend: ConcealmentBackend27
    private let logger = Logger(subsystem: "com.jordanbaird.Ice", category: "ConcealmentController27")
    private var live = [Live]()

    /// Whether any assertion is currently live.
    var isActive: Bool {
        !live.isEmpty
    }

    init(backend: ConcealmentBackend27) {
        self.backend = backend
    }

    /// Applies the target concealed sets for the currently running applications.
    ///
    /// If an activation fails, the assertions activated during this call are
    /// released, the previous ones stay live, and the error is rethrown.
    func apply(target: [Set<String>], running: Set<String>) async throws {
        // Timed: every apply has MenuBarAgent lay the bar out again, and that animation is
        // what a stutter of the bar would be made of.
        let started = ProcessInfo.processInfo.systemUptime
        logger.debug("Concealment apply: started, \(target.count, privacy: .public) sets")
        defer {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            logger.debug("Concealment apply: took \(milliseconds, privacy: .public) ms")
        }
        let desired = target.map { concealed in
            Spec(concealed: concealed, allowlist: ConcealmentPlanner27.allowlist(concealing: concealed, running: running))
        }
        var remaining = live
        var next = [Live]()
        var activated = [ConcealmentToken27]()
        do {
            for spec in desired {
                if let index = remaining.firstIndex(where: { $0.spec == spec }) {
                    next.append(remaining.remove(at: index))
                } else {
                    let token = try await backend.activate(allowedBundleIDs: spec.allowlist)
                    activated.append(token)
                    next.append(Live(spec: spec, token: token))
                }
            }
        } catch {
            for token in activated {
                backend.invalidate(token)
            }
            throw error
        }
        for old in remaining {
            backend.invalidate(old.token)
        }
        live = next
    }

    /// Releases every live assertion, which restores all items.
    func releaseAll() {
        // Timed like `apply`: releasing is the other half of the bar's movement, and it is
        // what a bridged click does before replaying itself.
        let started = ProcessInfo.processInfo.systemUptime
        logger.debug("Concealment release: started, \(self.live.count, privacy: .public) live")
        defer {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            logger.debug("Concealment release: took \(milliseconds, privacy: .public) ms")
        }
        for entry in live {
            backend.invalidate(entry.token)
        }
        live.removeAll()
    }
}
