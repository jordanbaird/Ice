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
                .onAppear(perform: onAppear)
                .environmentObject(appState)
                .environmentObject(appState.navigationState)
                .background(WindowAccessor { window in
                    window.level = .floating
                })
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 625)
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onReceiveWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.onReceiveWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
