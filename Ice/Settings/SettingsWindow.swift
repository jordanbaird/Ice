//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState
    let onAppear: () -> Void

    var body: some Scene {
        Window("Ice", id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 825, minHeight: 500)
                .onAppear(perform: onAppear)
                .environmentObject(appState)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 875, height: 575)
    }
}
