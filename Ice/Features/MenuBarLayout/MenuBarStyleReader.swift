//
//  MenuBarStyleReader.swift
//  Ice
//

import Combine
import SwiftUI
import ScreenCaptureKit

class MenuBarStyleReader: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private let calculator = ColorAverageCalculator(accuracy: .low)

    private var menuBar: SCWindow? {
        get async throws {
            try await SCShareableContent
                .excludingDesktopWindows(true, onScreenWindowsOnly: true)
                .windows
                .first {
                    $0.windowLayer == CGWindowLevelForKey(.mainMenuWindow) &&
                    $0.title == "Menubar"
                }
        }
    }

    private var wallpaperWindow: SCWindow? {
        get async throws {
            // macOS 14 uses a different name for the wallpaper image
            let namePrefix = if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 {
                "Wallpaper-"
            } else {
                "Desktop Picture"
            }
            return try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true)
                .windows
                .first {
                    $0.owningApplication?.bundleIdentifier == "com.apple.dock" &&
                    $0.isOnScreen &&
                    $0.title?.hasPrefix(namePrefix) == true
                }
        }
    }

    private var wallpaperBelowMenuBar: CGImage? {
        get async throws {
            guard
                let wallpaperWindow = try await wallpaperWindow,
                let menuBar = try await menuBar
            else {
                return nil
            }
            return try await WindowCaptureManager.captureImage(
                window: wallpaperWindow,
                bounds: menuBar.frame,
                resolution: .nominal
            )
        }
    }

    @Published var style: AnyShapeStyle = AnyShapeStyle(.background)

    init() {
        readAndUpdateStyle()
        configureCancellables()
    }

    private func configureCancellables() {
        // cancel and remove all current cancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.readAndUpdateStyle()
            }
            .store(in: &cancellables)
    }

    private func readAndUpdateStyle() {
        let semaphore = DispatchSemaphore(value: 0)
        Task { [weak self] in
            defer {
                semaphore.signal()
            }
            guard
                let self,
                let wallpaperBelowMenuBar = try await wallpaperBelowMenuBar,
                let components = calculator.calculateColorComponents(forImage: wallpaperBelowMenuBar)
            else {
                return
            }
            let color = Color(red: components.red, green: components.green, blue: components.blue)
            DispatchQueue.main.async {
                self.style = AnyShapeStyle(color)
            }
        }
        semaphore.wait()
    }
}
