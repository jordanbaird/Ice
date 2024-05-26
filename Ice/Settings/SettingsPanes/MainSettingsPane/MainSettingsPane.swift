//
//  MainSettingsPane.swift
//  Ice
//

import CompactSlider
import LaunchAtLogin
import SwiftUI

struct MainSettingsPane: View {
    @AppStorage("MainSettingsPaneSelectedTab")
    var selection: Int = 0

    var body: some View {
        CustomTabView(selection: $selection) {
            CustomTab("General") {
                GeneralSettingsTab()
            }
            CustomTab("Advanced") {
                AdvancedSettingsTab()
            }
        }
    }
}

#Preview {
    MainSettingsPane()
        .fixedSize()
        .buttonStyle(.custom)
        .environmentObject(AppState.shared)
}
