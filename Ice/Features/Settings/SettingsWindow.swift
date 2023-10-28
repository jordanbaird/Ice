//
//  SettingsWindow.swift
//  Ice
//

import SwiftUI

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState
    @State private var permissionsPresented = false

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .frame(minWidth: 700, minHeight: 400)
                .background {
                    Color.clear
                        .overlay(Material.thin)
                }
                .environmentObject(appState)
                .sheet(isPresented: $permissionsPresented) {
                    PermissionsView(
                        appState: appState,
                        isPresented: $permissionsPresented
                    )
                    .buttonStyle(.custom)
                }
                .onReceive(appState.permissionsManager.$hasPermissions) { hasPermissions in
                    if !hasPermissions {
                        permissionsPresented = true
                    }
                }
                .buttonStyle(.custom)
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
    }
}
