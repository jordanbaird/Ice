//
//  NSApplication+Activation.swift
//  Ice
//

import Cocoa

extension NSApplication {
    /// Activates the app and sets its activation policy to the given value.
    ///
    /// - Parameter policy: The activation policy to switch to.
    /// - Returns: `true` if the policy switch succeeded; otherwise `false`.
    @discardableResult
    func activate(withPolicy policy: ActivationPolicy) -> Bool {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
        return setActivationPolicy(policy)
    }

    /// Deactivates the app and sets its activation policy to the given value.
    ///
    /// - Parameter policy: The activation policy to switch to.
    /// - Returns: `true` if the policy switch succeeded; otherwise `false`.
    @discardableResult
    func deactivate(withPolicy policy: ActivationPolicy) -> Bool {
        if #available(macOS 14.0, *) {
            // FIXME: Seems like there should be a better way to simply deactivate and yield to the next available app,
            // but I'm not seeing one. Yielding to an empty bundle id is probably a bad (or at least not good) solution,
            // but `deactivate()` causes the app to be unfocused the next time it activates on macOS 14
            yieldActivation(toApplicationWithBundleIdentifier: "")
        } else {
            deactivate()
        }
        return setActivationPolicy(policy)
    }
}
