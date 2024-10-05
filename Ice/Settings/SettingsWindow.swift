//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        Window(Constants.settingsWindowTitle, id: Constants.settingsWindowID) {
            SettingsView()
                .readWindow { window in
                    guard let window else {
                        return
                    }
                    appState.assignSettingsWindow(window)
                }
                .frame(minWidth: 825, minHeight: 500)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 625)
        .environmentObject(appState)
        .environmentObject(appState.navigationState)
    }
}
