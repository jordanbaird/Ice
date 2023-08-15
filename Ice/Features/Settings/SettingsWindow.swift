//
//  SettingsWindow.swift
//  Ice
//

import Combine
import SwiftUI

struct SettingsWindow: Scene {
    private class Observer: ObservableObject {
        private var cancellables = Set<AnyCancellable>()

        @Published private(set) var titlebarHeight: CGFloat = 0

        private var window: NSWindow? {
            didSet {
                configureCancellables()
            }
        }

        init() {
            DispatchQueue.main.async {
                // async so that we don't try to access the app's windows
                // before they have been set
                self.configureCancellables()
            }
        }

        private func configureCancellables() {
            // cancel and remove all current cancellables
            for cancellable in cancellables {
                cancellable.cancel()
            }
            cancellables.removeAll()

            // observe the app's windows for changes and update our stored
            // window to the window that matches our identifier
            NSApp.publisher(for: \.windows)
                .didChange()
                .sink { [weak self] in
                    guard let window = NSApp.window(withIdentifier: Constants.settingsWindowID) else {
                        self?.window = nil
                        return
                    }
                    if self?.window !== window {
                        self?.window = window
                    }
                }
                .store(in: &cancellables)

            if let window {
                // we have a window; observe its frame and publish a new title
                // bar height when the frame changes
                window.publisher(for: \.frame)
                    .combineLatest(window.publisher(for: \.contentLayoutRect))
                    .map { $0.height - $1.height }
                    .sink { [weak self] titlebarHeight in
                        self?.titlebarHeight = titlebarHeight
                    }
                    .store(in: &cancellables)
            }
        }
    }

    @StateObject private var observer = Observer()

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .safeAreaInset(edge: .top, spacing: 0) { titlebar }
                .frame(minWidth: 700, minHeight: 400)
                .toolbar(.hidden, for: .windowToolbar)
                .background(Material.thin)
                .buttonStyle(SettingsButtonStyle())
        }
        .commandsRemoved()
        .defaultSize(width: 1080, height: 720)
    }

    private var titlebar: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .shadow(radius: 2.5)
            .frame(height: observer.titlebarHeight)
            .edgesIgnoringSafeArea(.top)
    }
}
