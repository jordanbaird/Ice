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
                .frame(minWidth: 840, minHeight: 520)
                .background {
                    Color.clear
                        .overlay(Material.thin)
                }
                .onAppear(perform: onAppear)
                .buttonStyle(.custom)
                .environmentObject(appState)
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
    }
}
