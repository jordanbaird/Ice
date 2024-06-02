//
//  MenuBarAppearanceSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MenuBarAppearanceEditor(location: .settings)
            .environmentObject(appState.menuBarManager.appearanceManager)
    }
}

#Preview {
    MenuBarAppearanceSettingsPane()
        .environmentObject(MenuBarAppearanceManager(appState: AppState()))
        .frame(width: 500, height: 300)
}
