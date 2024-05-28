//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        TabView {
            AboutTab()
                .tabItem {
                    Text("About")
                }
            UpdatesTab()
                .tabItem {
                    Text("Updates")
                }
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 6)
    }
}

#Preview {
    AboutSettingsPane()
}
