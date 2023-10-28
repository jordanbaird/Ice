//
//  AppState.swift
//  Ice
//

import Combine
import SwiftUI

class AppState: ObservableObject {
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)
    private(set) lazy var itemManager = MenuBarItemManager(appState: self)
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    let sharedContent = SharedContent()

    private(set) weak var settingsWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    init() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // propagate changes up from child observable objects
        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        itemManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissionsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        sharedContent.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    func setSettingsWindow(_ settingsWindow: NSWindow) {
        self.settingsWindow = settingsWindow
    }
}
