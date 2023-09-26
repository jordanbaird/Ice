//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @StateObject private var styleReader = MenuBarStyleReader()

    var body: some View {
        VStack(spacing: 20) {
            MenuBarLayoutView(layoutItems: .constant([]))
            MenuBarLayoutView(layoutItems: .constant([]))
            MenuBarLayoutView(layoutItems: .constant([]))
        }
        .padding()
        .environmentObject(styleReader)
    }
}

#Preview {
    MenuBarLayoutSettingsPane()
}
