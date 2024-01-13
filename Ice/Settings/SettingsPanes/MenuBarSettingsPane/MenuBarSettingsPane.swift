//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    var body: some View {
        MenuBarAppearanceTab()
            .bottomBar {
                HStack {
                    Spacer()
                    Button("Quit \(Constants.appName)") {
                        NSApp.terminate(nil)
                    }
                }
                .padding()
            }
    }
}

#Preview {
    MenuBarSettingsPane()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
