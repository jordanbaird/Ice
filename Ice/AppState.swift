//
//  AppState.swift
//  Ice
//

import Combine
import Foundation

class AppState: ObservableObject {
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)
    private(set) lazy var itemManager = MenuBarItemManager(appState: self)

    let permissionsManager = PermissionsManager()
    let sharedContent = SharedContent()

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
}
