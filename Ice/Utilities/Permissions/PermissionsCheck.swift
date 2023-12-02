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
    @Published private(set) var hasPermissions = false

    private let body: () -> Bool
    private var timerCancellable: (any Cancellable)?

    /// Creates a permissions check with the given closure.
    init(body: @escaping () -> Bool) {
        self.body = body
        start()
    }

    deinit {
        stop()
    }

    /// Starts running this permissions check.
    func start() {
        hasPermissions = body()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let hasPermissions = body()
                DispatchQueue.main.async {
                    self.hasPermissions = hasPermissions
                }
            }
    }

    /// Stops running this permissions check.
    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

// MARK: - AccessibilityPermissionsCheck
class AccessibilityPermissionsCheck: PermissionsCheck<AccessibilityRequest> {
    init() {
        super.init(body: AXIsProcessTrusted)
    }
}

// MARK: - ScreenCapturePermissionsCheck
// class ScreenCapturePermissionsCheck: PermissionsCheck<ScreenCaptureRequest> {
//     init() {
//         super.init(body: CGPreflightScreenCaptureAccess)
//     }
// }
