//
//  MenuBarColorReader.swift
//  Ice
//

import Combine
import ScreenCaptureKit
import SwiftUI

/// A type that reads and publishes the average color of the menu bar.
class MenuBarColorReader: ObservableObject {
    /// The color published by the reader.
    @Published var color = Color.defaultLayoutBar

    /// The menu bar whose color is read and published by the reader.
    private(set) weak var menuBar: MenuBar?

    private var cancellables = Set<AnyCancellable>()

    /// Creates a color reader that reads and publishes the average
    /// color of the given menu bar.
    init(menuBar: MenuBar) {
        self.menuBar = menuBar
    }

    /// Starts publishing the average color of the reader's ``menuBar``.
    ///
    /// The color can be subscribed to using the [$color](<doc:color>)
    /// publisher.
    func activate() {
        guard let sharedContent = menuBar?.sharedContent else {
            return
        }
        readAndUpdateColor(windows: sharedContent.windows)
        configureCancellables()
    }

    /// Stops publishing the average color of the reader's ``menuBar``,
    /// and sets the value of the reader's [$color](<doc:color>)
    /// publisher to its default value.
    func deactivate() {
        cancellables.removeAll()
        color = .defaultLayoutBar
    }

    /// Sets up a series of cancellables to respond to changes in
    /// the color reader's state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        menuBar?.sharedContent.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                self?.readAndUpdateColor(windows: windows)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Reads the average color of the menu bar and updates the reader's
    /// [$color](<doc:color>) publisher accordingly.
    private func readAndUpdateColor(windows: [SCWindow]) {
        // macOS 14 uses a different title for the wallpaper window
        let namePrefix = if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 {
            "Wallpaper-"
        } else {
            "Desktop Picture"
        }

        let wallpaperWindow = windows.first {
            // wallpaper window belongs to the Dock process
            $0.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            $0.isOnScreen &&
            $0.title?.hasPrefix(namePrefix) == true
        }
        let menuBarWindow = windows.first {
            // menu bar window belongs to the WindowServer process
            // (identified by an empty string)
            $0.owningApplication?.bundleIdentifier == "" &&
            $0.windowLayer == kCGMainMenuWindowLevel &&
            $0.title == "Menubar"
        }

        guard
            let wallpaperWindow,
            let menuBarWindow,
            let image = WindowCaptureManager.captureImage(
                windows: [wallpaperWindow],
                screenBounds: menuBarWindow.frame,
                options: .ignoreFraming
            ),
            let components = image.averageColor(
                accuracy: .low,
                algorithm: .simple
            )
        else {
            return
        }

        color = Color(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}
