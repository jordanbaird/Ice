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
        case menuBar = "Menu Bar"
        case hotkeys = "Hotkeys"
        case advanced = "Advanced"
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
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }

        private var image: Image {
            // returning the image explicitly instead of using a @ViewBuilder
            // lets us apply the resizable() modifier just once, in the `view`
            // property above
            switch self {
            case let .systemSymbol(name):
                return Image(systemName: name)
            case let .assetCatalog(resource):
                return Image(resource)
            }
        }
    }
}
