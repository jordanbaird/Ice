//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        IceWindow(id: .settings) {
            settingsView
                .frame(minWidth: 825, minHeight: 500)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 625)
        .environmentObject(appState)
        .environmentObject(appState.navigationState)
    }

    @ViewBuilder
    private var settingsView: some View {
        if #available(macOS 26.0, *) {
            SettingsView()
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            SettingsView()
        }
    }
}
