//
//  OnKeyDown.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that performs the given action when
    /// the specified key is pressed.
    func onKeyDown(
        key: KeyCode,
        isEnabled: Bool = true,
        action: @escaping () -> KeyCode.PressResult
    ) -> some View {
        localEventMonitor(mask: .keyDown, isEnabled: isEnabled) { event in
            if event.keyCode == key.rawValue {
                return switch action() {
                case .handled: nil
                case .ignored: event
                }
            }
            return event
        }
    }
}

extension KeyCode {
    /// A result value from a key press action that indicates
    /// whether the action consumed the event.
    enum PressResult {
        /// The action consumed the event, preventing dispatch
        /// from continuing.
        case handled

        /// The action ignored the event, allowing dispatch to
        /// continue.
        case ignored
    }
}
