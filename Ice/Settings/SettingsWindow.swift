//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState
    let onAppear: () -> Void

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 700, minHeight: 400)
                .onAppear(perform: onAppear)
                .environmentObject(appState)
        }
        .commandsRemoved()
        .defaultSize(width: 820, height: 550)
        .windowToolbarStyle(.unifiedCompact)
    }
}
