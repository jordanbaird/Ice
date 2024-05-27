//
//  MainSettingsPane.swift
//  Ice
//

import SwiftUI

struct MainSettingsPane: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Text("General")
                }
            AdvancedTab()
                .tabItem {
                    Text("Advanced")
                }
        }
        .padding()
    }
}

#Preview {
    MainSettingsPane()
        .fixedSize()
        .environmentObject(AppState.shared)
}
