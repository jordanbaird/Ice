//
//  PermissionsWindow.swift
//  Ice
//

import SwiftUI

struct PermissionsWindow: Scene {
    @ObservedObject var permissionsManager: PermissionsManager

    let onContinue: () -> Void

    init(appState: AppState, onContinue: @escaping () -> Void) {
        self.permissionsManager = appState.permissionsManager
        self.onContinue = onContinue
    }

    var body: some Scene {
        Window(Constants.permissionsWindowTitle, id: Constants.permissionsWindowID) {
            PermissionsView(onContinue: onContinue)
                .environmentObject(permissionsManager)
                .readWindow { window in
                    guard let window else {
                        return
                    }
                    window.styleMask.remove([.closable, .miniaturizable])
                    if let contentView = window.contentView {
                        with(contentView.safeAreaInsets) { insets in
                            insets.bottom = -insets.bottom
                            insets.left = -insets.left
                            insets.right = -insets.right
                            insets.top = -insets.top
                            contentView.additionalSafeAreaInsets = insets
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
