//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(label: "MenuBarItemService.Connection.queue", qos: .userInteractive)
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, logger: logger)
            self.queue = queue
            self.logger = logger
        }

        /// Starts the connection.
        func start() async {
            logger.debug("Starting MenuBarItemService connection")

            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .start) else {
                    logger.error("Start request returned nil")
                    continuation.resume()
                    return
                }
                if case .start = response {
                    continuation.resume()
                } else {
                    logger.error("Start request returned invalid response \(String(describing: response))")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .sourcePID(window)) else {
                    logger.error("Source PID request returned nil")
                    continuation.resume(returning: nil)
                    return
                }
                if case .sourcePID(let pid) = response {
                    continuation.resume(returning: pid)
                } else {
                    logger.error("Source PID request returned invalid response \(String(describing: response))")
                    continuation.resume(returning: nil)
                }
            }
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
            private var session: XPCSession?
            private let queue: DispatchQueue
            private let logger: Logger

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
            }

            private func getOrCreateSession() throws -> XPCSession {
                if let session {
                    return session
                }
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else {
                        return
                    }
                    logger.warning("Session was cancelled with error \(error.localizedDescription)")
                    self.session = nil
                }
                session.setPeerRequirement(.isFromSameTeam())
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                return session
            }

            func cancel(reason: String) {
                guard let session = session.take() else {
                    return
                }
                session.cancel(reason: reason)
            }

            func send(request: Request) -> Response? {
                do {
                    let session = try getOrCreateSession()
                    let reply = try session.sendSync(request)
                    return try reply.decode(as: Response.self)
                } catch {
                    logger.error("Session failed with error \(error)")
                    return nil
                }
            }
        }

        /// Protected storage for the underlying XPC session.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's logger.
        private let logger: Logger

        /// Creates a new session.
        init(queue: DispatchQueue, logger: Logger) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, logger: logger))
            self.queue = queue
            self.logger = logger
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) -> Response? {
            storage.withLock { $0.send(request: request) }
        }
    }
}
