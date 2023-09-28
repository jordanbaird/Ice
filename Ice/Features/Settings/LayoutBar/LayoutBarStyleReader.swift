//
//  LayoutBarStyleReader.swift
//  Ice
//

import Combine
import SwiftUI
import ScreenCaptureKit

class LayoutBarStyleReader: ObservableObject {
    static let defaultStyle = AnyShapeStyle(.defaultLayoutBar)

    private var cancellables = Set<AnyCancellable>()

    let windowList: WindowList

    let accuracy: ColorAverageAccuracy

    let algorithm: ColorAverageAlgorithm

    let alphaThreshold: CGFloat

    @Published var style = defaultStyle

    init(
        windowList: WindowList,
        accuracy: ColorAverageAccuracy = .low,
        algorithm: ColorAverageAlgorithm = .simple,
        alphaThreshold: CGFloat = 0.5
    ) {
        self.windowList = windowList
        self.accuracy = accuracy
        self.algorithm = algorithm
        self.alphaThreshold = alphaThreshold
    }

    func activate() {
        readAndUpdateStyle(windows: windowList.windows)
        configureCancellables()
    }

    func deactivate() {
        cancellables.removeAll()
        style = Self.defaultStyle
    }

    /// Sets up a series of cancellables to respond to important
    /// changes in the style reader's state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        windowList.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                self?.readAndUpdateStyle(windows: windows)
            }
            .store(in: &c)

        cancellables = c
    }

    private func readAndUpdateStyle(windows: [SCWindow]) {
        // macOS 14 uses a different title for the wallpaper window
        let namePrefix = if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 {
            "Wallpaper-"
        } else {
            "Desktop Picture"
        }

        let wallpaperWindow = windows.first {
            $0.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            $0.isOnScreen &&
            $0.title?.hasPrefix(namePrefix) == true
        }
        let menuBarWindow = windows.first {
            $0.owningApplication?.bundleIdentifier == "" && // WindowServer is identified by an empty string
            $0.windowLayer == kCGMainMenuWindowLevel &&
            $0.title == "Menubar"
        }

        guard
            let wallpaperWindow,
            let menuBarWindow,
            let image = WindowCaptureManager.captureImage(
                window: wallpaperWindow,
                bounds: menuBarWindow.frame
            ),
            let components = image.averageColor(
                accuracy: accuracy,
                algorithm: algorithm,
                alphaThreshold: alphaThreshold
            )
        else {
            return
        }

        style = AnyShapeStyle(
            Color(
                red: components.red,
                green: components.green,
                blue: components.blue
            )
        )
    }
}
