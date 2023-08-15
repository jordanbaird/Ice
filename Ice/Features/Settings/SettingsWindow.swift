//
//  SettingsWindow.swift
//  Ice
//

import Combine
import SwiftUI

private class SettingsWindowObserver: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    /// The height of the observed window's title bar, computed by
    /// subtracting the window's content height from the height of
    /// the window itself.
    @Published private(set) var titlebarHeight: CGFloat = 0

    /// A Boolean value indicating whether the observed window is
    /// the app's current key window.
    @Published private(set) var isKeyWindow: Bool = false

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
            // we have a window; subscribe to changes to its state across
            // several publishers and update the corresponding @Published
            // property when a change occurs
            window.publisher(for: \.frame)
                .combineLatest(window.publisher(for: \.contentLayoutRect))
                .map { $0.height - $1.height }
                .sink { [weak self] titlebarHeight in
                    self?.titlebarHeight = titlebarHeight
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                .sink { [weak self, weak window] notification in
                    if notification.object as? NSWindow === window {
                        self?.isKeyWindow = true
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
                .sink { [weak self, weak window] notification in
                    if notification.object as? NSWindow === window {
                        self?.isKeyWindow = false
                    }
                }
                .store(in: &cancellables)
        }
    }
}

struct SettingsWindow: Scene {
    @StateObject private var observer = SettingsWindowObserver()

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .safeAreaInset(edge: .top, spacing: 0) { titlebar }
                .frame(minWidth: 700, minHeight: 400)
                .toolbar(.hidden, for: .windowToolbar)
                .background(
                    Color.clear
                        .overlay(Material.thin)
                )
                .buttonStyle(SettingsButtonStyle())
        }
        .commandsRemoved()
        .defaultSize(width: 1080, height: 720)
    }

    private var titlebar: some View {
        VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
            .frame(height: observer.titlebarHeight)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EnvironmentReader(\.colorScheme) { colorScheme in
                    Color(white: colorScheme == .dark ? 0 : 0.7)
                        .opacity(observer.isKeyWindow ? 1 : 0.5)
                }
                .frame(height: 1)
            }
            .edgesIgnoringSafeArea(.top)
    }
}
