//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import AppKit
import Foundation
import OSLog
import os.lock

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(logger: logger)
            self.logger = logger
        }

        /// Starts the connection.
        func start() async {
            logger.debug("Starting MenuBarItemService connection")

            guard let response = await session.send(request: .start) else {
                logger.error("Start request returned nil")
                return
            }
            guard case .start = response else {
                logger.error("Start request returned invalid response \(String(describing: response))")
                return
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            let query = SourcePIDQuery(windowID: window.windowID, bounds: window.bounds)

            guard let response = await session.send(request: .sourcePID(query)) else {
                logger.error("Source PID request returned nil")
                return nil
            }
            guard case .sourcePID(let pid) = response else {
                logger.error("Source PID request returned invalid response \(String(describing: response))")
                return nil
            }
            if let pid, NSRunningApplication(processIdentifier: pid) == nil {
                // The service returned a PID that doesn't belong to any
                // running application, so the response is either forged
                // or stale. Don't trust it.
                logger.error("Service returned PID \(pid), which has no running application. Discarding response")
                return nil
            }
            return pid
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private final class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name

            /// Protects the session object. Requests are sent outside
            /// this lock so that a slow or unresponsive service can't
            /// freeze the callers.
            private let sessionLock = OSAllocatedUnfairLock<XPCSession?>(initialState: nil)

            private let queue: DispatchQueue
            private let logger: Logger

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
            }

            private func clearSession() {
                // Cancel the session before dropping our reference.
                // Deallocating an active session traps in
                // _xpc_api_misuse.
                let session = sessionLock.withLock { (state: inout XPCSession?) -> XPCSession? in
                    let session = state
                    state = nil
                    return session
                }
                session?.cancel(reason: "Session was cancelled")
            }

            func getOrCreateSession() throws -> XPCSession {
                try sessionLock.withLock { (state: inout XPCSession?) -> XPCSession in
                    if let session = state {
                        return session
                    }
                    let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                        guard let self else {
                            return
                        }
                        logger.warning("Session was cancelled with error \(error.localizedDescription)")
                        clearSession()
                    }
                    if CodeSigningInfo.shouldEnforceSameTeamRequirement {
                        session.setPeerRequirement(.isFromSameTeam())
                    } else {
                        CodeSigningInfo.logPeerVerificationDecision()
                    }
                    session.setTargetQueue(queue)
                    try session.activate()
                    state = session
                    return session
                }
            }
        }

        /// Protected storage for the underlying XPC session.
        private let storage: Storage

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's logger.
        private let logger: Logger

        /// Creates a new session.
        init(logger: Logger) {
            // XPC requires the session's target queue to be serial;
            // using a concurrent queue traps in _xpc_api_misuse as soon
            // as a reply handler is registered. Reply handling here is
            // just a decode and a continuation resume, so a serial queue
            // does not limit throughput.
            let queue = DispatchQueue(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive
            )
            self.storage = Storage(queue: queue, logger: logger)
            self.queue = queue
            self.logger = logger
        }

        /// Sends the given request to the service and returns the
        /// response, or nil if the request failed.
        func send(request: Request) async -> Response? {
            guard let session = try? storage.getOrCreateSession() else {
                logger.error("Session failed")
                return nil
            }
            do {
                // Use the XPCReceivedMessage-returning overload; the
                // Reply-decoding sendSync overload traps in
                // _xpc_api_misuse at runtime.
                let reply = try session.sendSync(request)
                return try reply.decode(as: Response.self)
            } catch {
                logger.error("Session failed with error \(error)")
                return nil
            }
        }
    }
}
