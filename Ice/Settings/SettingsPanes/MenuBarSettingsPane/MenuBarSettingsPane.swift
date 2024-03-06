//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    @AppStorage("MenuBarSettingsPaneSelectedTab")
    var selection: Int = 0

    var body: some View {
        CustomTabView(selection: $selection) {
            CustomTab("Appearance") {
                MenuBarAppearanceTab(location: .settings)
            }
            CustomTab("Layout") {
                MenuBarLayoutTab()
            }
        }
    }
}

#Preview {
    MenuBarSettingsPane()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
