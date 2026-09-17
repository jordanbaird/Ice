//
//  UserNotificationManager.swift
//  Ice
//

import OSLog
import UserNotifications

/// Manager for user notifications.
@MainActor
final class UserNotificationManager: NSObject {
    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The current notification center.
    var notificationCenter: UNUserNotificationCenter { .current() }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        notificationCenter.delegate = self
    }

    /// Requests authorization to allow user notifications for the app.
    func requestAuthorization() {
        Task {
            do {
                try await notificationCenter.requestAuthorization(options: [.badge, .alert, .sound])
            } catch {
                Logger.default.error("Failed to request notification authorization: \(error)")
            }
        }
    }

    /// Schedules the delivery of a local notification.
    func addRequest(with identifier: UserNotificationIdentifier, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: identifier.rawValue,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    /// Removes the notifications from Notification Center that match the given identifiers.
    func removeDeliveredNotifications(with identifiers: [UserNotificationIdentifier]) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers.map { $0.rawValue })
    }
}

// MARK: UserNotificationManager: UNUserNotificationCenterDelegate
extension UserNotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard let appState else {
            return
        }

        switch UserNotificationIdentifier(rawValue: response.notification.request.identifier) {
        case .updateCheck:
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
                break
            }
            appState.updatesManager.checkForUpdates()
        case nil:
            break
        }
    }
}
