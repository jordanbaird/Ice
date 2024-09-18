//
//  ScreenStateManager.swift
//  Ice
//

import Cocoa
import Combine

final class ScreenStateManager {
    static let shared = ScreenStateManager()

    private(set) var screenIsLocked = false

    private(set) var screenSaverIsActive = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        configureCancellables()
    }

    static func setUpSharedManager() {
        _ = shared
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = false
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = false
            }
            .store(in: &c)

        cancellables = c
    }
}
