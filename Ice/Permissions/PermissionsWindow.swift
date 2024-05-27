//
//  PermissionsWindow.swift
//  Ice
//

import SwiftUI

struct PermissionsWindow: Scene {
    @ObservedObject var appState: AppState
    let onContinue: () -> Void

    var body: some Scene {
        Window("Permissions", id: Constants.permissionsWindowID) {
            PermissionsView(onContinue: onContinue)
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
