//
//  PermissionsManager.swift
//  Ice
//

import Combine

/// A type that manages the permissions of the app.
@MainActor
final class PermissionsManager: ObservableObject {
    /// A Boolean value that indicates whether the app has been granted all permissions.
    @Published var hasAllPermissions: Bool = false

    let accessibilityPermission = AccessibilityPermission()

    let screenRecordingPermission = ScreenRecordingPermission()

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        accessibilityPermission.$hasPermission
            .combineLatest(screenRecordingPermission.$hasPermission)
            .sink { [weak self] hasPermission1, hasPermission2 in
                self?.hasAllPermissions = hasPermission1 && hasPermission2
            }
            .store(in: &c)

        cancellables = c
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        accessibilityPermission.stopCheck()
        screenRecordingPermission.stopCheck()
    }
}
