//
//  PermissionsManager.swift
//  Ice
//

import Combine
import Foundation

/// A type that manages the permissions of the app.
@MainActor
final class PermissionsManager: ObservableObject {
    /// The state of the granted permissions for the app.
    enum PermissionsState {
        case missingPermissions
        case hasAllPermissions
        case hasRequiredPermissions
    }

    /// The state of the granted permissions for the app.
    @Published var permissionsState = PermissionsState.missingPermissions

    let accessibilityPermission: AccessibilityPermission

    let screenRecordingPermission: ScreenRecordingPermission

    let allPermissions: [Permission]

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    var requiredPermissions: [Permission] {
        allPermissions.filter { $0.isRequired }
    }

    init(appState: AppState) {
        self.appState = appState
        self.accessibilityPermission = AccessibilityPermission()
        self.screenRecordingPermission = ScreenRecordingPermission()
        self.allPermissions = [
            accessibilityPermission,
            screenRecordingPermission,
        ]
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge(
            accessibilityPermission.$hasPermission.mapToVoid(),
            screenRecordingPermission.$hasPermission.mapToVoid()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else {
                return
            }
            if allPermissions.allSatisfy({ $0.hasPermission }) {
                permissionsState = .hasAllPermissions
            } else if requiredPermissions.allSatisfy({ $0.hasPermission }) {
                permissionsState = .hasRequiredPermissions
            } else {
                permissionsState = .missingPermissions
                return
            }
            // If the app has all required permissions, stop the periodic checks.
            // This is important for performance, as the periodic checks can be expensive.
            stopTimerChecks()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Stops the periodic permission checks, keeping one-shot observers alive.
    ///
    /// Only required permissions are stopped. Optional ones keep polling: the
    /// user can grant them at any point from System Settings, and nothing else
    /// re-checks them, so freezing them here left the app reporting a
    /// permission as missing for the rest of the session even after it had
    /// been granted (issue #22). Each check is rate limited inside
    /// `ScreenCapture`, so a poll costs at most one check per couple of seconds
    /// rather than one per tick.
    func stopTimerChecks() {
        for permission in requiredPermissions {
            permission.stopTimerCheck()
        }
    }
}
