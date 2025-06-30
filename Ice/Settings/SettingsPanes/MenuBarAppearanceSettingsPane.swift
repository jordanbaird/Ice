//
//  MenuBarAppearanceSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MenuBarAppearanceEditor(location: .settings)
            .environmentObject(appState.appearanceManager)
    }
}
