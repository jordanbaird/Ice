//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    let menuBarManager: MenuBarManager

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 700, minHeight: 400)
                .background {
                    Color.clear
                        .overlay(Material.thin)
                }
                .environmentObject(menuBarManager)
                .buttonStyle(.custom)
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
    }
}
