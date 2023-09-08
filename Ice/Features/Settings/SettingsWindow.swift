//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @StateObject private var statusBar = StatusBar()

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 700, minHeight: 400)
                .toolbar(.hidden, for: .windowToolbar)
                .background(
                    Color.clear
                        .overlay(Material.thin)
                )
                .buttonStyle(SettingsButtonStyle())
                .environmentObject(statusBar)
                .task {
                    if !ProcessInfo.processInfo.isPreview {
                        statusBar.initializeSections()
                    }
                }
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
        .windowStyle(.hiddenTitleBar)
    }
}
