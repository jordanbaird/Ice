//
//  PermissionsWindow.swift
//  Ice
//

import SwiftUI

struct PermissionsWindow: Scene {
    @ObservedObject var appState: AppState
    @AppStorage(AppLanguage.setupCompletedKey) private var hasSelectedLanguage = false

    var body: some Scene {
        Window(Constants.permissionsWindowTitle, id: Constants.permissionsWindowID) {
            Group {
                if hasSelectedLanguage {
                    PermissionsView()
                        .environmentObject(appState.permissionsManager)
                } else {
                    InitialLanguageView()
                }
            }
                .readWindow { window in
                    guard let window else {
                        return
                    }
                    appState.assignPermissionsWindow(window)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
