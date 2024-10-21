//
//  MenuBarAutoExpander.swift
//  Ice
//
//  Created by Michele Primavera on 21/10/24.
//

import Cocoa
import Combine

final class MenuBarAutoExpander : ObservableObject {
    /// The shared app state.
    private weak var appState: AppState?
    
    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a cache with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the cache.
    @MainActor
    func performSetup() {
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge(
                NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).mapToVoid(),
                Just(())
            )
            .throttle(for: 10.0, scheduler: DispatchQueue.main, latest: false)
            .sink {
                let advancedSettingsManager = appState.settingsManager.advancedSettingsManager
                
                if(advancedSettingsManager.showHiddenSectionWhenWidthGreaterThanEnabled) {
                    Task.detached {
                        let mainScreen = NSScreen.main
                        if mainScreen != nil {
                            let mainScreenWidth = mainScreen!.frame.width
                            
                            guard let section = await appState.menuBarManager.section(withName: .hidden) else {
                                return
                            }
                            
                            let setting = await advancedSettingsManager.showHiddenSectionWhenWidthGreaterThan
                            
                            if (mainScreenWidth >= setting) {
                                Logger.autoExpander.info("Showing hidden section because mainScreenWidth (\(mainScreenWidth)) >= showHiddenSectionWhenWidthGreaterThan (\(setting)")
                                await section.show()
                            } else {
                                Logger.autoExpander.info("Hiding hidden section because mainScreenWidth (\(mainScreenWidth)) < showHiddenSectionWhenWidthGreaterThan (\(setting)")
                                await section.hide()
                            }
                        }
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }
}

// MARK: - Logger
private extension Logger {
    static let autoExpander = Logger(category: "MenuBarAutoExpander")
}
