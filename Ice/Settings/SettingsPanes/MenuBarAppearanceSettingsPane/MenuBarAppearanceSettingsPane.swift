//
//  MenuBarAppearanceSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    var body: some View {
        MenuBarAppearanceEditor(location: .settings)
    }
}

#Preview {
    MenuBarAppearanceSettingsPane()
        .environmentObject(AppState())
        .frame(width: 500, height: 300)
}
