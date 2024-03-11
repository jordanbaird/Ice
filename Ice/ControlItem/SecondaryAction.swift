//
//  SecondaryAction.swift
//  Ice
//

import SwiftUI

enum SecondaryAction: Int, CaseIterable {
    case toggleAlwaysHiddenSection = 0

    var localized: LocalizedStringKey {
        switch self {
        case .toggleAlwaysHiddenSection:
            "Toggle \"always hidden\" section"
        }
    }
}
