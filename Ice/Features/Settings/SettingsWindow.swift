//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @StateObject private var menuBar = MenuBar()

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 700, minHeight: 400)
                .background {
                    Color.clear
                        .overlay(Material.thin)
                }
                .task {
                    if !ProcessInfo.processInfo.isPreview {
                        menuBar.initializeSections()
                    }
                }
                .environmentObject(menuBar)
                .environmentObject(menuBar.itemManager)
                .buttonStyle(SettingsButtonStyle())
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
    }
}
