//
//  SecondaryAction.swift
//  Ice
//

import SwiftUI

enum SecondaryAction: Int, CaseIterable {
    case noAction = 1000
    case toggleAlwaysHiddenSection = 0

    var localized: LocalizedStringKey {
        switch self {
        case .noAction:
            "No action"
        case .toggleAlwaysHiddenSection:
            "Toggle \"always hidden\" section"
        }
    }

    /// Performs the action.
    /// - Parameter appState: The shared app state.
    /// - Returns: A Boolean value indicating whether the action was performed.
    func perform(with appState: AppState) -> Bool {
        switch self {
        case .noAction:
            return false
        case .toggleAlwaysHiddenSection:
            if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden) {
                alwaysHiddenSection.toggle()
            }
            return true
        }
    }
}
