//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    @AppStorage(Defaults.menuBarSettingsPaneSelectedTab) var selection: Int = 0

    var body: some View {
        CustomTabView(selection: $selection) {
            Tab {
                Text("Layout")
            } content: {
                MenuBarSettingsPaneLayoutTab()
            }
            Tab {
                Text("Appearance")
            } content: {
                MenuBarSettingsPaneAppearanceTab()
            }
        }
    }
}
