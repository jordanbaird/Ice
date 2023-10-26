//
//  PermissionsManager.swift
//  Ice
//

import Combine

class PermissionsManager: ObservableObject {
    let accessibilityGroup = AccessibilityPermissionsGroup()
    let screenCaptureGroup = ScreenCapturePermissionsGroup()

    @Published var hasPermissions: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        accessibilityGroup.$hasPermissions
            .combineLatest(screenCaptureGroup.$hasPermissions)
            .sink { [weak self] hasAccessibilityPermissions, hasScreenCapturePermissions in
                self?.hasPermissions = hasAccessibilityPermissions && hasScreenCapturePermissions
            }
            .store(in: &c)

        cancellables = c
    }

    func stopAllChecks() {
        accessibilityGroup.check.stop()
        screenCaptureGroup.check.stop()
    }
}
