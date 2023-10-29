//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    @ObservedObject var appState = AppState.shared

    var body: some Scene {
        SettingsWindow(appState: appState)
    }

    init() {
        NSSplitViewItem.swizzle()
    }
}
