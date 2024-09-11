//
//  PermissionsWindow.swift
//  Ice
//

import SwiftUI

struct PermissionsWindow: Scene {
    @ObservedObject var permissionsManager: PermissionsManager

    init(appState: AppState) {
        self.permissionsManager = appState.permissionsManager
    }

    var body: some Scene {
        permissionsWindow
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)
            .environmentObject(permissionsManager)
    }

    private var permissionsWindow: some Scene {
        if #available(macOS 15.0, *) {
            return PermissionsWindowMacOS15()
        } else {
            return PermissionsWindowMacOS14()
        }
    }
}

@available(macOS 14.0, *)
private struct PermissionsWindowMacOS14: Scene {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        Window(Constants.permissionsWindowTitle, id: Constants.permissionsWindowID) {
            PermissionsView()
                .once {
                    dismissWindow(id: Constants.permissionsWindowID)
                }
        }
    }
}

@available(macOS 15.0, *)
private struct PermissionsWindowMacOS15: Scene {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launchBehavior: SceneLaunchBehavior = .presented

    var body: some Scene {
        Window(Constants.permissionsWindowTitle, id: Constants.permissionsWindowID) {
            PermissionsView()
                .once {
                    dismissWindow(id: Constants.permissionsWindowID)
                    launchBehavior = .suppressed // Suppress the scene after first dismissing.
                }
        }
        .defaultLaunchBehavior(launchBehavior)
    }
}
