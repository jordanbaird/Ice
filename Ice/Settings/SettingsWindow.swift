//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState

    let onAppear: () -> Void

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
            return SettingsWindowMacOS15(onAppear: onAppear)
        } else {
            return SettingsWindowMacOS14(onAppear: onAppear)
        }
    }
}

@available(macOS 14.0, *)
private struct SettingsWindowMacOS14: Scene {
    let onAppear: () -> Void

    var body: some Scene {
        Window(Constants.settingsWindowTitle, id: Constants.settingsWindowID) {
            SettingsView()
                .once(perform: onAppear)
        }
    }
}

@available(macOS 15.0, *)
private struct SettingsWindowMacOS15: Scene {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launchBehavior: SceneLaunchBehavior = .presented

    let onAppear: () -> Void

    var body: some Scene {
        Window(Constants.settingsWindowTitle, id: Constants.settingsWindowID) {
            SettingsView()
                .once {
                    onAppear()
                    dismissWindow(id: Constants.settingsWindowID)
                    launchBehavior = .suppressed // Suppress the scene after first dismissing.
                }
        }
        .defaultLaunchBehavior(launchBehavior)
    }
}
