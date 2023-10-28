//
//  PermissionsManager.swift
//  Ice
//

import Combine

class PermissionsManager: ObservableObject {
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

    func stopAllChecks() {
        accessibilityGroup.check.stop()
        screenCaptureGroup.check.stop()
    }
}
