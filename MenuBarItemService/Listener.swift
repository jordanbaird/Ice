//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import XPC

/// A wrapper around an xpc listener object.
final class Listener {
    /// An error that can be thrown during listener activation.
    enum ActivationError: Error, CustomStringConvertible {
        case alreadyActive
        case failure(any Error)

        var description: String {
            switch self {
            case .alreadyActive:
                "Listener is already active"
            case .failure(let error):
                "Listener activation failed with error \(error)"
            }
        }
    }

    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying xpc listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                SourcePIDCache.shared.start()
                return .start
            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            }
        } catch {
            Logger.general.error("Service failed with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    ///
    /// - Note: This method throws an error if called on an active listener.
    func activate() throws {
        guard listener == nil else {
            throw ActivationError.alreadyActive
        }
        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            throw ActivationError.failure(error)
        }
    }

    /// Cancels the listener.
    func cancel() {
        listener.take()?.cancel()
    }
}
