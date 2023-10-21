//
//  MenuBarManager.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit
import SwiftUI

/// Manager for the state of the menu bar.
final class MenuBarManager: ObservableObject {
    /// A type that specifies how the menu bar is tinted.
    enum TintKind: Int {
        /// The menu bar is not tinted.
        case none
        /// The menu bar is tinted with a solid color.
        case solid
        /// The menu bar is tinted with a gradient.
        case gradient
    }

    /// Set to `true` to tell the menu bar to save its sections.
    @Published var needsSave = false

    /// The menu bar's window.
    @Published var menuBarWindow: SCWindow?

    /// The tint kind currently in use.
    @Published var tintKind: TintKind

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor?

    /// The user's currently chosen tint gradient.
    @Published var tintGradient: CustomGradient?

    /// The average color of the menu bar.
    ///
    /// If ``publishesAverageColor`` is `false`, this property is
    /// set to `nil`.
    @Published var averageColor: CGColor?

    /// A Boolean value that indicates whether the average color of
    /// the menu bar should be actively published.
    ///
    /// If this property is `false`, the ``averageColor`` property
    /// is set to `nil`.
    @Published var publishesAverageColor = false

    /// The sections currently in the menu bar.
    @Published private(set) var sections = [MenuBarSection]() {
        willSet {
            for section in sections {
                section.menuBarManager = nil
            }
        }
        didSet {
            if validateSectionCountOrReinitialize() {
                for section in sections {
                    section.menuBarManager = self
                }
            }
            configureCancellables()
            needsSave = true
        }
    }

    let sharedContent = SharedContent()

    private(set) lazy var itemManager = MenuBarItemManager(menuBarManager: self)
    private lazy var overlayPanel = MenuBarOverlayPanel(menuBarManager: self)
    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar instance.
    init() {
        self.tintKind = TintKind(rawValue: UserDefaults.standard.integer(forKey: Defaults.menuBarTintKind)) ?? .none
        if let tintColorData = UserDefaults.standard.data(forKey: Defaults.menuBarTintColor) {
            do {
                self.tintColor = try JSONDecoder().decode(CodableColor.self, from: tintColorData).cgColor
            } catch {
                Logger.menuBarManager.error("Error decoding color: \(error)")
            }
        }
        if let tintGradientData = UserDefaults.standard.data(forKey: Defaults.menuBarTintGradient) {
            do {
                self.tintGradient = try JSONDecoder().decode(CustomGradient.self, from: tintGradientData)
            } catch {
                Logger.menuBarManager.error("Error decoding gradient: \(error)")
            }
        }
        configureCancellables()
    }

    /// Performs the initial setup of the menu bar's section list.
    func initializeSections() {
        guard sections.isEmpty else {
            Logger.menuBarManager.info("Sections already initialized")
            return
        }

        // load sections from persistent storage
        sections = (UserDefaults.standard.array(forKey: Defaults.sections) ?? []).compactMap { entry in
            guard let dictionary = entry as? [String: Any] else {
                Logger.menuBarManager.error("Entry not convertible to dictionary")
                return nil
            }
            do {
                return try DictionaryDecoder().decode(MenuBarSection.self, from: dictionary)
            } catch {
                Logger.menuBarManager.error("Decoding error: \(error)")
                return nil
            }
        }
    }

    /// Save all control items in the menu bar to persistent storage.
    func saveSections() {
        do {
            let serializedSections = try sections.map { section in
                try DictionaryEncoder().encode(section)
            }
            UserDefaults.standard.set(serializedSections, forKey: Defaults.sections)
            needsSave = false
        } catch {
            Logger.menuBarManager.error("Encoding error: \(error)")
        }
    }

    /// Performs validation on the current section count, reinitializing
    /// the sections if needed.
    ///
    /// - Returns: A Boolean value indicating whether the count was valid.
    private func validateSectionCountOrReinitialize() -> Bool {
        if sections.count != 3 {
            sections = [
                MenuBarSection(name: .visible, autosaveName: "Item-1", position: 0),
                MenuBarSection(name: .hidden, autosaveName: "Item-2", position: 1),
                // don't give the always-hidden section an initial position,
                // so that its item is placed at the far end of the menu bar
                MenuBarSection(name: .alwaysHidden, autosaveName: "Item-3", state: .hideItems),
            ]
            return false
        }
        return true
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // update the control item for each section when the
        // position of one changes
        Publishers.MergeMany(sections.map { $0.controlItem.$position })
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let sortedControlItems = sections.lazy
                    .map { section in
                        section.controlItem
                    }
                    .sorted { first, second in
                        // invisible items should preserve their ordering
                        if !first.isVisible {
                            return false
                        }
                        if !second.isVisible {
                            return true
                        }
                        // expanded items should preserve their ordering
                        switch (first.state, second.state) {
                        case (.showItems, .showItems):
                            return (first.position ?? 0) < (second.position ?? 0)
                        case (.hideItems, _):
                            return !first.expandsOnHide
                        case (_, .hideItems):
                            return second.expandsOnHide
                        }
                    }
                // assign the items to their new sections
                for index in 0..<sections.count {
                    sections[index].controlItem = sortedControlItems[index]
                }
            }
            .store(in: &c)

        $needsSave
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveSections()
                }
            }
            .store(in: &c)

        sharedContent.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                guard let self else {
                    return
                }
                menuBarWindow = windows.first {
                    // menu bar window belongs to the WindowServer process
                    // (identified by an empty string)
                    $0.owningApplication?.bundleIdentifier == "" &&
                    $0.windowLayer == kCGMainMenuWindowLevel &&
                    $0.title == "Menubar"
                }
                if publishesAverageColor {
                    readAndUpdateAverageColor(windows: windows)
                }
            }
            .store(in: &c)

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
                        Logger.menuBarManager.error("Error encoding color: \(error)")
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
                        Logger.menuBarManager.error("Error encoding gradient: \(error)")
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
                if publishesAverageColor {
                    readAndUpdateAverageColor(windows: sharedContent.windows)
                } else {
                    averageColor = nil
                }
            }
            .store(in: &c)

        // propagate changes up from child observable objects
        sharedContent.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        itemManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        for section in sections {
            section.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
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

        averageColor = CGColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - MenuBarOverlayPanel
private class MenuBarOverlayPanel: NSPanel {
    private static let defaultAlphaValue = 0.2

    private(set) weak var menuBarManager: MenuBarManager?

    private var cancellables = Set<AnyCancellable>()

    init(menuBarManager: MenuBarManager) {
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
        self.menuBarManager = menuBarManager
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

        if let menuBarManager {
            Publishers.CombineLatest3(
                menuBarManager.$tintKind,
                menuBarManager.$tintColor,
                menuBarManager.$tintGradient
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
                    let menuBarManager,
                    menuBarManager.tintKind != .none
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
            Logger.menuBarManager.info("No screen")
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

        guard let menuBarManager else {
            return
        }

        switch menuBarManager.tintKind {
        case .none:
            break
        case .solid:
            guard
                let tintColor = menuBarManager.tintColor,
                let nsColor = NSColor(cgColor: tintColor)
            else {
                return
            }
            backgroundColor = nsColor
        case .gradient:
            guard
                let tintGradient = menuBarManager.tintGradient,
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
    static let menuBarManager = mainSubsystem(category: "MenuBarManager")
}
