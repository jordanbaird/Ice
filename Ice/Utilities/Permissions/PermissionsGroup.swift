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

    private var cancellable: Cancellable?

    /// Creates a permission with the given permissions check, title,
    /// details, and notes.
    ///
    /// - Parameters:
    ///   - check: The check associated with the permission.
    ///   - title: The permission's title.
    ///   - details: Details that describe the reasons the app needs
    ///     this permission.
    ///   - notes: Contextual notes that further explain the permission.
    init(check: Check, title: String, details: [String] = [], notes: [String] = []) {
        self.check = check
        self.request = Request()
        self.title = title
        self.details = details
        self.notes = notes
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
                    if #available(macOS 14.0, *) {
                        NSApp.activate()
                    } else {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    cancellable = nil
                }
            }
    }
}

// MARK: - AccessibilityPermissionsGroup
class AccessibilityPermissionsGroup: PermissionsGroup<AccessibilityRequest, AccessibilityPermissionsCheck> {
    init() {
        super.init(
            check: AccessibilityPermissionsCheck(),
            title: "Accessibility",
            details: [
                "Arrange individual menu bar items.",
            ]
        )
    }
}

// MARK: - ScreenCapturePermissionsGroup
class ScreenCapturePermissionsGroup: PermissionsGroup<ScreenCaptureRequest, ScreenCapturePermissionsCheck> {
    init() {
        super.init(
            check: ScreenCapturePermissionsCheck(),
            title: "Screen Capture",
            details: [
                "Get real-time information about your menu bar items.",
                "Capture images of your menu bar items for display.",
            ],
            notes: [
                "\(Constants.appName) does not record your screen.",
            ]
        )
    }
}
