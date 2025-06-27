//
//  IceBarColorManager.swift
//  Ice
//

import Cocoa
import Combine

final class IceBarColorManager: ObservableObject {
    private struct WindowImageInfo {
        let image: CGImage
        let source: MenuBarAverageColorInfo.Source
    }

    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImageInfo: WindowImageInfo?

    private var cancellables = Set<AnyCancellable>()

    init(iceBarPanel: IceBarPanel) {
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

            Publishers.CombineLatest(
                iceBarPanel.publisher(for: \.frame),
                iceBarPanel.publisher(for: \.isVisible)
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame, isVisible in
                guard
                    let self,
                    let screen = iceBarPanel.screen,
                    isVisible,
                    screen == .main
                else {
                    return
                }
                updateColorInfo(with: frame, screen: screen)
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
                    updateColorInfo(with: iceBarPanel.frame, screen: screen)
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImageInfo(for screen: NSScreen) {
        let windows = WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
        let displayID = screen.displayID

        if #available(macOS 26.0, *) {
            if let window = WindowInfo.getWallpaperWindow(from: windows, for: displayID) {
                let bounds = with(window.frame) { $0.size.height = 1 }
                if let image = ScreenCapture.captureWindow(window.windowID, screenBounds: bounds, option: .nominalResolution) {
                    windowImageInfo = WindowImageInfo(image: image, source: .desktopWallpaper)
                } else {
                    windowImageInfo = nil
                }
            }
        } else {
            if
                let window = WindowInfo.getMenuBarWindow(from: windows, for: displayID),
                let image = ScreenCapture.captureWindow(window.windowID, option: .nominalResolution)
            {
                windowImageInfo = WindowImageInfo(image: image, source: .menuBarWindow)
            } else {
                windowImageInfo = nil
            }
        }
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let windowImageInfo else {
            colorInfo = nil
            return
        }

        let image = windowImageInfo.image
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -50, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            colorInfo = nil
            return
        }

        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: windowImageInfo.source)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImageInfo(for: screen)
        updateColorInfo(with: frame, screen: screen)
    }
}
