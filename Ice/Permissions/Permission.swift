//
//  Permission.swift
//  Ice
//

import AXSwift
import Combine
import Cocoa

// MARK: - Permission

class Permission: ObservableObject {
    /// A Boolean value that indicates whether the user has granted this permission.
    @Published private(set) var hasPermission = false

    let title: String
    let details: [String]

    private let check: () -> Bool
    private let request: () -> Void

    private var timerCancellable: AnyCancellable?
    private var hasPermissionCancellable: AnyCancellable?

    init(
        title: String,
        details: [String],
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.check = check
        self.request = request
        self.hasPermission = check()
    }

    deinit {
        stopCheck()
    }

    /// Runs the permission check. If the user has not granted permission, performs
    /// the request and waits for the user to respond. When permission is granted,
    /// performs the given completion handler.
    func runWithCompletion(_ completionHandler: @escaping () -> Void) {
        if check() {
            hasPermission = true
        } else {
            hasPermission = false
            request()
            timerCancellable = Timer.publish(every: 1, on: .main, in: .default)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    let hasPermission = check()
                    DispatchQueue.main.async {
                        self.hasPermission = hasPermission
                    }
                }
            hasPermissionCancellable = $hasPermission
                .sink { [weak self] hasPermission in
                    guard let self else {
                        return
                    }
                    if hasPermission {
                        if let app = NSWorkspace.shared.frontmostApplication {
                            NSRunningApplication.current.activate(from: app)
                        } else {
                            NSApp.activate()
                        }
                        completionHandler()
                        stopCheck()
                    }
                }
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
        hasPermissionCancellable?.cancel()
        hasPermissionCancellable = nil
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: "Accessibility",
            details: [
                "Get real-time information about the menu bar.",
                "Move individual menu bar items.",
            ],
            check: {
                checkIsProcessTrusted()
            },
            request: {
                checkIsProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: "Screen Recording",
            details: [
                "Apply custom styling to the menu bar.",
                "Display images of individual menu bar items.",
            ],
            check: {
                CGPreflightScreenCaptureAccess()
            },
            request: {
                CGRequestScreenCaptureAccess()
            }
        )
    }
}
