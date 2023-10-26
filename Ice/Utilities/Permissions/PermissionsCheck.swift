//
//  PermissionsCheck.swift
//  Ice
//

import ApplicationServices
import Combine
import Foundation

// MARK: - PermissionsCheck
class PermissionsCheck<Request: PermissionsRequest>: ObservableObject {
    @Published var hasPermissions: Bool

    let queue = DispatchQueue(label: "Permissions Check Queue")
    var timer: QueuedTimer?

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
