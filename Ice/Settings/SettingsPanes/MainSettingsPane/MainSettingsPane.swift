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
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 6)
    }
}

#Preview {
    MainSettingsPane()
        .fixedSize()
        .environmentObject(AppState.shared)
}
