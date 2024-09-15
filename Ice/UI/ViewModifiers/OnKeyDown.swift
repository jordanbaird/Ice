//
//  OnKeyDown.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that performs the given action when
    /// the specified key is pressed.
    func onKeyDown(key: KeyCode, action: @escaping () -> Void) -> some View {
        localEventMonitor(mask: .keyDown) { event in
            if event.keyCode == key.rawValue {
                action()
                return nil
            }
            return event
        }
    }
}
