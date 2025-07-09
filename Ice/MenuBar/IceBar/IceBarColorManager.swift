//
//  IceBarColorManager.swift
//  Ice
//

import Combine
import SwiftUI

final class IceBarColorManager: ObservableObject {
    private struct WindowImageInfo {
        let image: CGImage
        let source: MenuBarAverageColorInfo.Source
    }

    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImageInfo: WindowImageInfo?

    private var cancellables = Set<AnyCancellable>()

    func performSetup(with iceBarPanel: IceBarPanel) {
        self.iceBarPanel = iceBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let iceBarPanel {
            iceBarPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen,
                        screen == .main
                    else {
                        return
                    }
                    updateWindowImageInfo(for: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceBarPanel] isVisible in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        isVisible,
                        screen == .main
                    else {
                        return
                    }
                    updateColorInfo(with: iceBarPanel.frame, screen: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak iceBarPanel] frame in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        iceBarPanel.isVisible,
                        screen == .main
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            Publishers.Merge4(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ()),
                Timer.publish(every: 5, on: .main, in: .default)
                    .autoconnect()
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak iceBarPanel] in
                guard
                    let self,
                    let iceBarPanel,
                    let screen = iceBarPanel.screen,
                    screen == .main
                else {
                    return
                }
                updateWindowImageInfo(for: screen)
                if iceBarPanel.isVisible {
                    withAnimation {
                        self.updateColorInfo(with: iceBarPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImageInfo(for screen: NSScreen) {
        let windows = WindowInfo.getWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.getWallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
        let bounds = with(wallpaperWindow.bounds) { $0.size.height = 1 }
        let option: CGWindowImageOption = .nominalResolution

        guard let image = ScreenCapture.captureWindows(windowIDs, screenBounds: bounds, option: option) else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether it contributes to the capture.
        windowImageInfo = WindowImageInfo(image: image, source: .menuBarWindow)
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let windowImageInfo else {
            return
        }

        let image = windowImageInfo.image
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: windowImageInfo.source)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImageInfo(for: screen)
        updateColorInfo(with: frame, screen: screen)
    }
}
