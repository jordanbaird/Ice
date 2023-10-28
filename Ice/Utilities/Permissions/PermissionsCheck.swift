//
//  PermissionsCheck.swift
//  Ice
//

import ApplicationServices
import Combine
import Foundation

// MARK: - PermissionsCheck
class PermissionsCheck<Request: PermissionsRequest>: ObservableObject {
    /// A Boolean value that indicates whether the app has been
    /// granted this permission.
    @Published private(set) var hasPermissions: Bool

    private let queue = DispatchQueue(label: "Permissions Check Queue")
    private var timer: QueuedTimer?

    /// Creates a permissions check with the given closure.
    init(body: @escaping () -> Bool) {
        self.hasPermissions = body()
        let timer = QueuedTimer(interval: 1, queue: queue) { [weak self] timer in
            let hasPermissions = body()
            DispatchQueue.main.async {
                self?.hasPermissions = hasPermissions
            }
        }
        timer.start()
        self.timer = timer
    }

    deinit {
        timer?.stop()
    }

    /// Stops running this permissions check.
    func stop() {
        timer?.stop()
    }
}

// MARK: - AccessibilityPermissionsCheck
class AccessibilityPermissionsCheck: PermissionsCheck<AccessibilityRequest> {
    init() {
        super.init(body: AXIsProcessTrusted)
    }
}

// MARK: - ScreenCapturePermissionsCheck
class ScreenCapturePermissionsCheck: PermissionsCheck<ScreenCaptureRequest> {
    init() {
        super.init(body: CGPreflightScreenCaptureAccess)
    }
}
