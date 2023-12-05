//
//  PermissionsManager.swift
//  Ice
//

import Combine

/// A type that manages the permissions of the app.
class PermissionsManager: ObservableObject {
    /// A Boolean value that indicates whether the app has been
    /// granted all permissions.
    @Published var hasPermissions: Bool = false

    private(set) lazy var accessibilityGroup = AccessibilityPermissionsGroup(permissionsManager: self)
    private(set) lazy var screenCaptureGroup = ScreenCapturePermissionsGroup(permissionsManager: self)
    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        accessibilityGroup.$hasPermissions
            .combineLatest(screenCaptureGroup.$hasPermissions)
            .sink { [weak self] hasPermissions1, hasPermissions2 in
                self?.hasPermissions = hasPermissions1 && hasPermissions2
            }
            .store(in: &c)

        cancellables = c
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        accessibilityGroup.check.stop()
        screenCaptureGroup.check.stop()
    }
}
