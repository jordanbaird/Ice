//
//  IceBarColorManager.swift
//  Ice
//

import Cocoa
import Combine

@MainActor
class IceBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImage: CGImage?

    private var cancellables = Set<AnyCancellable>()

    init(iceBarPanel: IceBarPanel) {
        self.iceBarPanel = iceBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let iceBarPanel {
            iceBarPanel.publisher(for: \.screen)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen
                    else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
                .store(in: &c)

            Publishers.CombineLatest(
                iceBarPanel.publisher(for: \.frame),
                iceBarPanel.publisher(for: \.isVisible)
            )
            .sink { [weak self] frame, isVisible in
                guard
                    let self,
                    let screen = iceBarPanel.screen,
                    isVisible
                else {
                    return
                }
                updateColorInfo(with: frame, screen: screen)
            }
            .store(in: &c)

            Publishers.Merge4(
                NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).mapToVoid(),
                NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).mapToVoid(),
                DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification")).mapToVoid(),
                Timer.publish(every: 5, on: .main, in: .default).autoconnect().mapToVoid()
            )
            .sink { [weak self] in
                guard let self else {
                    return
                }
                if let screen = iceBarPanel.screen {
                    updateWindowImage(for: screen)
                    if iceBarPanel.isVisible {
                        updateColorInfo(with: iceBarPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImage(for screen: NSScreen) {
        let displayID = screen.displayID
        if
            let window = WindowInfo.getMenuBarWindow(for: displayID),
            let image = Bridging.captureWindow(window.windowID, option: .nominalResolution)
        {
            windowImage = image
        } else {
            windowImage = nil
        }
    }

    func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let windowImage else {
            colorInfo = nil
            return
        }

        let percentage = ((frame.midX - screen.frame.origin.x) / screen.frame.width).clamped(to: 0...1)
        let bounds = CGRect(
            x: frame.origin.x + (frame.width * percentage),
            y: 0,
            width: 0,
            height: 1
        ).insetBy(dx: -10, dy: 0)
        print(bounds.minX, bounds.maxX)

        guard
            let croppedImage = windowImage.cropping(to: bounds),
            let averageColor = croppedImage.averageColor(resolution: .low)
        else {
            return
        }

        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }
}
