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
                .background {
                    VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                        .opacity(0.25)
                        .blendMode(.softLight)
                }
                .onAppear(perform: onAppear)
                .environmentObject(appState)
                .environmentObject(appState.navigationState)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 625)
    }
}
