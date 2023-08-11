//
//  SettingsItem.swift
//  Ice
//

import SwiftUI

struct SettingsItem: Hashable, Identifiable {
    let name: Name
    let icon: IconResource
    let primaryColor: Color
    let secondaryColor: Color
    var id: Int { name.hashValue }

    init(
        name: Name,
        icon: IconResource,
        primaryColor: Color? = nil,
        secondaryColor: Color? = nil
    ) {
        self.name = name
        self.icon = icon
        self.primaryColor = primaryColor ?? Color(.linkColor)
        self.secondaryColor = secondaryColor ?? Color(.windowBackgroundColor)
    }
}

extension SettingsItem {
    enum Name: String {
        case general = "General"
        case menuBarLayout = "Menu Bar Layout"
        case about = "About"

        var localized: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }
    }
}

extension SettingsItem {
    enum IconResource: Hashable {
        case systemSymbol(_ name: String)
        case assetCatalog(_ name: String)
    }
}
