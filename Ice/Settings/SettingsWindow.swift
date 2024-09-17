//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        settingsWindow
            .commandsRemoved()
            .windowResizability(.contentSize)
            .defaultSize(width: 900, height: 625)
            .environmentObject(appState)
            .environmentObject(appState.navigationState)
    }

    private var settingsWindow: some Scene {
        if #available(macOS 15.0, *) {
            return window
                .defaultLaunchBehavior(.presented)
        } else {
            return window
        }
    }

    @SceneBuilder
    private var window: some Scene {
        Window(Constants.settingsWindowTitle, id: Constants.settingsWindowID) {
            SettingsView()
                .once {
                    openWindow(id: Constants.permissionsWindowID)
                }
        }
    }
}
