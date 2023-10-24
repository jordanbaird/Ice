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

    /// A Boolean value that indicates whether the menu bar should
    /// have a shadow.
    @Published var hasShadow: Bool

    /// The tint kind currently in use.
    @Published var tintKind: TintKind

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor?

    /// The user's currently chosen tint gradient.
    @Published var tintGradient = CustomGradient.defaultMenuBarTint

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
    private lazy var shadowPanel = MenuBarShadowPanel(menuBarManager: self)

    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar instance.
    init() {
        self.hasShadow = UserDefaults.standard.bool(forKey: Defaults.menuBarHasShadow)
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

        $hasShadow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasShadow in
                guard let self else {
                    return
                }
                UserDefaults.standard.set(hasShadow, forKey: Defaults.menuBarHasShadow)
                if hasShadow {
                    shadowPanel.showIfAble(fadeIn: true)
                } else {
                    shadowPanel.hide()
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
                    overlayPanel.showIfAble(fadeIn: true)
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
                            overlayPanel.showIfAble(fadeIn: true)
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
                guard let self else {
                    return
                }
                guard case .gradient = tintKind else {
                    overlayPanel.hide()
                    return
                }
                do {
                    let data = try JSONEncoder().encode(tintGradient)
                    UserDefaults.standard.set(data, forKey: Defaults.menuBarTintGradient)
                    overlayPanel.showIfAble(fadeIn: true)
                } catch {
                    Logger.menuBarManager.error("Error encoding gradient: \(error)")
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

// MARK: - Logger
private extension Logger {
    static let menuBarManager = mainSubsystem(category: "MenuBarManager")
}
