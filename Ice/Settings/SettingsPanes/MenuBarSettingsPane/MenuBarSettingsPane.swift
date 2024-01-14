//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    var body: some View {
        MenuBarAppearanceTab()
    }
}

#Preview {
    MenuBarSettingsPane()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
