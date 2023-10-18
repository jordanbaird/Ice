//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    @AppStorage(Defaults.menuBarSettingsPaneSelectedTab) var selection: Int = 0

    var body: some View {
        CustomTabView(selection: $selection) {
            CustomTab {
                Text("Layout")
            } content: {
                MenuBarSettingsPaneLayoutTab()
            }
            CustomTab {
                Text("Appearance")
            } content: {
                MenuBarSettingsPaneAppearanceTab()
            }
        }
    }
}
