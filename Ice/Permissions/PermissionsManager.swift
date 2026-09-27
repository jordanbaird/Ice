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

        Publishers.CombineLatest(
            accessibilityPermission.$hasPermission,
            screenRecordingPermission.$hasPermission
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] accessibility, screenRecording in
            guard let self else {
                return
            }
            if accessibility && screenRecording {
                permissionsState = .hasAllPermissions
            } else if accessibility {
                permissionsState = .hasRequiredPermissions
            } else {
                permissionsState = .missingPermissions
            }
        }
        .store(in: &c)

        cancellables = c
    }

    /// 进入授权页时恢复检查。
    func startAllChecks() {
        for permission in allPermissions {
            permission.startCheck()
        }
    }

    func refreshAll() {
        for permission in allPermissions {
            permission.refresh()
        }
    }

    /// 停止权限检查。
    func stopAllChecks() {
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
