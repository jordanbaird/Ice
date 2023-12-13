//
//  PermissionsGroup.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - PermissionsGroup
class PermissionsGroup<Request: PermissionsRequest, Check: PermissionsCheck<Request>>: ObservableObject {
    /// A Boolean value that indicates whether the app has been
    /// granted this permission.
    @Published var hasPermissions = false

    /// The check associated with the permission.
    let check: Check
    /// The request associated with the permission.
    let request: Request
    /// The permission's title.
    let title: String
    /// Details that describe the reasons the app needs this permission.
    let details: [String]
    /// Contextual notes that further explain the permission.
    let notes: [String]

    var hasPermissionsHandler: (() -> Void)?

    private weak var appState: AppState?
    private var cancellable: (any Cancellable)?

    /// Creates a permission with the given permissions check, title,
    /// details, and notes.
    ///
    /// - Parameters:
    ///   - check: The check associated with the permission.
    ///   - title: The permission's title.
    ///   - details: Details that describe the reasons the app needs
    ///     this permission.
    ///   - notes: Contextual notes that further explain the permission.
    ///   - appState: The global app state.
    init(check: Check, title: String, details: [String], notes: [String], appState: AppState?) {
        self.check = check
        self.request = Request()
        self.title = title
        self.details = details
        self.notes = notes
        self.appState = appState
        self.check.$hasPermissions.assign(to: &$hasPermissions)
    }

    /// Performs the request associated with the permission.
    ///
    /// Once the request has been performed, this function
    /// waits for the user to grant permission, then activates
    /// the app.
    func performRequest() {
        request.perform()
        cancellable = $hasPermissions
            .sink { [weak self] hasPermissions in
                guard let self else {
                    return
                }
                if hasPermissions {
                    if let app = NSWorkspace.shared.frontmostApplication {
                        NSRunningApplication.current.activate(from: app)
                    } else {
                        NSApp.activate()
                    }
                    hasPermissionsHandler?()
                    cancellable = nil
                }
            }
    }
}

// MARK: - AccessibilityPermissionsGroup
class AccessibilityPermissionsGroup: PermissionsGroup<AccessibilityRequest, AccessibilityPermissionsCheck> {
    init(permissionsManager: PermissionsManager) {
        super.init(
            check: AccessibilityPermissionsCheck(),
            title: "Accessibility",
            details: [
                "Get real-time information about the menu bar.",
                // "Arrange individual menu bar items.",
            ],
            notes: [],
            appState: permissionsManager.appState
        )
    }
}

// MARK: - ScreenCapturePermissionsGroup
class ScreenCapturePermissionsGroup: PermissionsGroup<ScreenCaptureRequest, ScreenCapturePermissionsCheck> {
    init(permissionsManager: PermissionsManager) {
        super.init(
            check: ScreenCapturePermissionsCheck(),
            title: "Screen Recording",
            details: [
                "Apply custom styling to the menu bar.",
                // "Capture images of menu bar items for display.",
            ],
            notes: [
                "\(Constants.appName) does not record your screen.",
            ],
            appState: permissionsManager.appState
        )
    }
}
