//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    @AppStorage(Defaults.menuBarSettingsPaneSelectedTab) var selection: Int = 0

    var body: some View {
        IceTabView(selection: $selection) {
            IceTab {
                Text("Layout")
            } content: {
                MenuBarSettingsPaneLayoutTab()
            }
            IceTab {
                Text("Appearance")
            } content: {
                MenuBarSettingsPaneAppearanceTab()
            }
        }
    }
}
