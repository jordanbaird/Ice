//
//  SettingsNavigationItem.swift
//  Ice
//

import SwiftUI

struct SettingsNavigationItem: Hashable, Identifiable {
    let name: Name
    let icon: IconResource
    var id: Int { name.hashValue }
}

extension SettingsNavigationItem {
    enum Name: String {
        case general = "General"
        case menuBarItems = "Menu Bar Items"
        case menuBarAppearance = "Menu Bar Appearance"
        case hotkeys = "Hotkeys"
        case advanced = "Advanced"
        case updates = "Updates"
        case about = "About"

        var localized: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }
    }
}

extension SettingsNavigationItem {
    enum IconResource: Hashable {
        case systemSymbol(_ name: String)
        case assetCatalog(_ resource: ImageResource)

        var view: some View {
            image.resizable().aspectRatio(contentMode: .fit)
        }

        private var image: Image {
            switch self {
            case .systemSymbol(let name):
                Image(systemName: name)
            case .assetCatalog(let resource):
                Image(resource)
            }
        }
    }
}
