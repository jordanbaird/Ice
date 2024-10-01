//
//  PermissionsWindow.swift
//  Ice
//

import SwiftUI

struct PermissionsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        Window(Constants.permissionsWindowTitle, id: Constants.permissionsWindowID) {
            PermissionsView()
                .readWindow { window in
                    guard let window else {
                        return
                    }
                    appState.assignPermissionsWindow(window)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .environmentObject(appState.permissionsManager)
    }
}
