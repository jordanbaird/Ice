//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import ScreenCaptureKit

// MARK: - MenuBarAppearanceManager

final class MenuBarAppearanceManager: ObservableObject {
    /// A type that specifies how the menu bar is tinted.
    enum TintKind: Int {
        /// The menu bar is not tinted.
        case none
        /// The menu bar is tinted with a solid color.
        case solid
        /// The menu bar is tinted with a gradient.
        case gradient
    }

    /// The tint kind currently in use.
    @Published var tintKind: TintKind

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor?

    /// The user's currently chosen tint gradient.
    @Published var tintGradient: CustomGradient?

    /// A Boolean value that indicates whether the average color of
    /// the menu bar should be actively published.
    ///
    /// If this property is `false`, the ``averageColor`` property
    /// is set to `nil`.
    @Published var publishesAverageColor = false

    /// The average color of the menu bar.
    ///
    /// If ``publishesAverageColor`` is `false`, this property is
    /// set to `nil`.
    @Published var averageColor: CGColor?

    private(set) weak var menuBar: MenuBar?
    private lazy var overlayPanel = MenuBarOverlayPanel(appearanceManager: self)

    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        self.tintKind = TintKind(rawValue: UserDefaults.standard.integer(forKey: Defaults.menuBarTintKind)) ?? .none
        if let tintColorData = UserDefaults.standard.data(forKey: Defaults.menuBarTintColor) {
            do {
                self.tintColor = try JSONDecoder().decode(CodableColor.self, from: tintColorData).cgColor
            } catch {
                Logger.appearanceManager.error("Error decoding color: \(error)")
            }
        }
        if let tintGradientData = UserDefaults.standard.data(forKey: Defaults.menuBarTintGradient) {
            do {
                self.tintGradient = try JSONDecoder().decode(CustomGradient.self, from: tintGradientData)
            } catch {
                Logger.appearanceManager.error("Error decoding gradient: \(error)")
            }
        }
        self.menuBar = menuBar
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $tintKind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tintKind in
                guard let self else {
                    return
                }
                UserDefaults.standard.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
                switch tintKind {
                case .none:
                    overlayPanel.hide()
                case .solid, .gradient:
                    overlayPanel.show()
                }
            }
            .store(in: &c)

        $tintColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tintColor in
                guard
                    let self,
                    tintKind == .solid
                else {
                    return
                }
                if let tintColor {
                    do {
                        let data = try JSONEncoder().encode(CodableColor(cgColor: tintColor))
                        UserDefaults.standard.set(data, forKey: Defaults.menuBarTintColor)
                        if case .solid = tintKind {
                            overlayPanel.show()
                        }
                    } catch {
                        Logger.appearanceManager.error("Error encoding color: \(error)")
                        overlayPanel.hide()
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: Defaults.menuBarTintColor)
                    overlayPanel.hide()
                }
            }
            .store(in: &c)

        $tintGradient
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tintGradient in
                guard
                    let self,
                    tintKind == .gradient
                else {
                    return
                }
                if
                    let tintGradient,
                    !tintGradient.stops.isEmpty
                {
                    do {
                        let data = try JSONEncoder().encode(tintGradient)
                        UserDefaults.standard.set(data, forKey: Defaults.menuBarTintGradient)
                        if case .gradient = tintKind {
                            overlayPanel.show()
                        }
                    } catch {
                        Logger.appearanceManager.error("Error encoding gradient: \(error)")
                        overlayPanel.hide()
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: Defaults.menuBarTintGradient)
                    overlayPanel.hide()
                }
            }
            .store(in: &c)

        $publishesAverageColor
            .sink { [weak self] publishesAverageColor in
                guard let self else {
                    return
                }
                // immediately update the average color
                if 
                    publishesAverageColor,
                    let sharedContent = menuBar?.sharedContent
                {
                    readAndUpdateAverageColor(windows: sharedContent.windows)
                } else {
                    averageColor = nil
                }
            }
            .store(in: &c)

        menuBar?.sharedContent.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                guard let self else {
                    return
                }
                if publishesAverageColor {
                    readAndUpdateAverageColor(windows: windows)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func readAndUpdateAverageColor(windows: [SCWindow]) {
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

        guard
            let wallpaperWindow,
            let menuBarWindow = menuBar?.window,
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

        averageColor = CGColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }
}

// MARK: MenuBarAppearanceManager: BindingExposable
extension MenuBarAppearanceManager: BindingExposable { }

// MARK: - MenuBarOverlayPanel

private class MenuBarOverlayPanel: NSPanel {
    private static let defaultAlphaValue = 0.2

    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    private var cancellables = Set<AnyCancellable>()

    init(appearanceManager: MenuBarAppearanceManager) {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        self.appearanceManager = appearanceManager
        self.title = "Menu Bar Overlay"
        self.level = .statusBar
        self.collectionBehavior = [
            .fullScreenNone,
            .ignoresCycle,
        ]
        self.ignoresMouseEvents = true
        self.contentView?.wantsLayer = true
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appearanceManager {
            Publishers.CombineLatest3(
                appearanceManager.$tintKind,
                appearanceManager.$tintColor,
                appearanceManager.$tintGradient
            )
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateTint()
                }
            }
            .store(in: &c)
        }

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                hide()
                if
                    let appearanceManager,
                    appearanceManager.tintKind != .none
                {
                    show()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    func show() {
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        guard let screen = NSScreen.main else {
            Logger.appearanceManager.info("No screen")
            return
        }
        setFrame(
            CGRect(
                x: screen.frame.minX,
                y: screen.visibleFrame.maxY + 1,
                width: screen.frame.width,
                height: (screen.frame.height - screen.visibleFrame.height) - 1
            ),
            display: true
        )
        let isVisible = isVisible
        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()
        if !isVisible {
            animator().alphaValue = Self.defaultAlphaValue
        }
    }

    func hide() {
        orderOut(nil)
    }

    /// Updates the tint of the panel according to the appearance
    /// manager's tint kind.
    func updateTint() {
        backgroundColor = .clear
        contentView?.layer = CALayer()

        guard let appearanceManager else {
            return
        }

        switch appearanceManager.tintKind {
        case .none:
            break
        case .solid:
            guard
                let tintColor = appearanceManager.tintColor,
                let nsColor = NSColor(cgColor: tintColor)
            else {
                return
            }
            backgroundColor = nsColor
        case .gradient:
            guard
                let tintGradient = appearanceManager.tintGradient,
                !tintGradient.stops.isEmpty
            else {
                return
            }
            let gradientLayer = CAGradientLayer()
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0)
            if tintGradient.stops.count == 1 {
                // gradient layer needs at least two stops to render correctly;
                // convert the single stop into two and place them on opposite
                // ends of the layer
                let color = tintGradient.stops[0].color
                gradientLayer.colors = [color, color]
                gradientLayer.locations = [0, 1]
            } else {
                let sortedStops = tintGradient.stops.sorted { $0.location < $1.location }
                gradientLayer.colors = sortedStops.map { $0.color }
                gradientLayer.locations = sortedStops.map { $0.location } as [NSNumber]
            }
            contentView?.layer = gradientLayer
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let appearanceManager = mainSubsystem(category: "MenuBarAppearanceManager")
}
