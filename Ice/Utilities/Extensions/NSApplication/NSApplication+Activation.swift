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
        activate(ignoringOtherApps: true)
        return setActivationPolicy(policy)
    }

    /// Deactivates the app and sets its activation policy to the given value.
    ///
    /// - Parameter policy: The activation policy to switch to.
    /// - Returns: `true` if the policy switch succeeded; otherwise `false`.
    @discardableResult
    func deactivate(withPolicy policy: ActivationPolicy) -> Bool {
        deactivate()
        return setActivationPolicy(policy)
    }
}
