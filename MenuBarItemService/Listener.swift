//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .sourcePID(let query):
                let pid = SourcePIDCache.shared.pid(for: query)
                return .sourcePID(pid)
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws -> XPCListener {
        try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws -> XPCListener {
        try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            try activateWithRetries(maxAttempts: 3)
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Repeatedly attempts to activate the listener. Retrying prevents
    /// a transient failure (such as the service name being momentarily
    /// taken by another process) from leaving the service permanently
    /// unable to answer requests.
    private func activateWithRetries(maxAttempts: Int) throws {
        var lastError: Error?

        for attempt in 1...max(1, maxAttempts) {
            do {
                try activateUnchecked()
                return
            } catch {
                lastError = error
                Logger.default.error("Failed to activate listener (attempt \(attempt, privacy: .public)): \(error)")
                Thread.sleep(forTimeInterval: 1)
            }
        }

        throw lastError!
    }

    /// Activates the listener without checking if it is already active.
    private func activateUnchecked() throws {
        if #available(macOS 26.0, *) {
            // Same-team peer requirements cannot be satisfied by
            // processes without a team identifier, such as ad-hoc
            // signed local builds, so only enforce them when we have
            // a team of our own.
            CodeSigningInfo.logPeerVerificationDecision()
            if CodeSigningInfo.shouldEnforceSameTeamRequirement {
                listener = try uncheckedActivateWithSameTeamRequirement()
            } else {
                listener = try uncheckedActivate()
            }
        } else {
            listener = try uncheckedActivate()
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}
