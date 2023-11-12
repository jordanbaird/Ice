//
//  MenuBar.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit
import SwiftUI

/// Manager for the state of the menu bar.
final class MenuBar: ObservableObject {
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

    /// A Boolean value that indicates whether the menu bar should
    /// have a shadow.
    @Published var hasShadow: Bool

    /// A Boolean value that indicates whether the menu bar should
    /// have a border.
    @Published var hasBorder: Bool

    /// The color of the menu bar's border.
    @Published var borderColor: CGColor = .black

    /// The width of the menu bar's border.
    @Published var borderWidth: Double

    /// The tint kind currently in use.
    @Published var tintKind: TintKind

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor = .black

    /// The user's currently chosen tint gradient.
    @Published var tintGradient: CustomGradient = .defaultMenuBarTint

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
                section.menuBar = nil
            }
        }
        didSet {
            if validateSectionCountOrReinitialize() {
                for section in sections {
                    section.menuBar = self
                }
            }
            configureCancellables()
            needsSave = true
        }
    }

    private weak var appState: AppState?
    private lazy var overlayPanel = MenuBarOverlayPanel(menuBar: self)
    private lazy var backingPanel = MenuBarBackingPanel(menuBar: self)

    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar instance.
    init(appState: AppState) {
        self.appState = appState
        self.hasShadow = UserDefaults.standard.bool(forKey: Defaults.menuBarHasShadow)
        self.hasBorder = UserDefaults.standard.bool(forKey: Defaults.menuBarHasBorder)
        self.borderWidth = UserDefaults.standard.object(forKey: Defaults.menuBarBorderWidth) as? Double ?? 1
        self.tintKind = TintKind(rawValue: UserDefaults.standard.integer(forKey: Defaults.menuBarTintKind)) ?? .none
        if let borderColorData = UserDefaults.standard.data(forKey: Defaults.menuBarBorderColor) {
            do {
                self.borderColor = try JSONDecoder().decode(CodableColor.self, from: borderColorData).cgColor
            } catch {
                Logger.menuBar.error("Error decoding border color: \(error)")
            }
        }
        if let tintColorData = UserDefaults.standard.data(forKey: Defaults.menuBarTintColor) {
            do {
                self.tintColor = try JSONDecoder().decode(CodableColor.self, from: tintColorData).cgColor
            } catch {
                Logger.menuBar.error("Error decoding tint color: \(error)")
            }
        }
        if let tintGradientData = UserDefaults.standard.data(forKey: Defaults.menuBarTintGradient) {
            do {
                self.tintGradient = try JSONDecoder().decode(CustomGradient.self, from: tintGradientData)
            } catch {
                Logger.menuBar.error("Error decoding tint gradient: \(error)")
            }
        }
        configureCancellables()
    }

    /// Performs the initial setup of the menu bar's section list.
    func initializeSections() {
        guard sections.isEmpty else {
            Logger.menuBar.info("Sections already initialized")
            return
        }

        // load sections from persistent storage
        sections = (UserDefaults.standard.array(forKey: Defaults.sections) ?? []).compactMap { entry in
            guard let dictionary = entry as? [String: Any] else {
                Logger.menuBar.error("Entry not convertible to dictionary")
                return nil
            }
            do {
                return try DictionaryDecoder().decode(MenuBarSection.self, from: dictionary)
            } catch {
                Logger.menuBar.error("Decoding error: \(error)")
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
            Logger.menuBar.error("Encoding error: \(error)")
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

        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                if publishesAverageColor {
                    readAndUpdateAverageColor()
                }
            }
            .store(in: &c)

        $hasShadow
            .receive(on: DispatchQueue.main)
            .sink { hasShadow in
                UserDefaults.standard.set(hasShadow, forKey: Defaults.menuBarHasShadow)
            }
            .store(in: &c)

        $hasBorder
            .receive(on: DispatchQueue.main)
            .sink { hasBorder in
                UserDefaults.standard.set(hasBorder, forKey: Defaults.menuBarHasBorder)
            }
            .store(in: &c)

        $borderColor
            .receive(on: DispatchQueue.main)
            .sink { borderColor in
                do {
                    let data = try JSONEncoder().encode(CodableColor(cgColor: borderColor))
                    UserDefaults.standard.set(data, forKey: Defaults.menuBarBorderColor)
                } catch {
                    Logger.menuBar.error("Error encoding border color: \(error)")
                }
            }
            .store(in: &c)

        $borderWidth
            .receive(on: DispatchQueue.main)
            .sink { borderWidth in
                UserDefaults.standard.set(borderWidth, forKey: Defaults.menuBarBorderWidth)
            }
            .store(in: &c)

        $tintKind
            .receive(on: DispatchQueue.main)
            .sink { tintKind in
                UserDefaults.standard.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
            }
            .store(in: &c)

        $tintColor
            .receive(on: DispatchQueue.main)
            .sink { tintColor in
                do {
                    let data = try JSONEncoder().encode(CodableColor(cgColor: tintColor))
                    UserDefaults.standard.set(data, forKey: Defaults.menuBarTintColor)
                } catch {
                    Logger.menuBar.error("Error encoding tint color: \(error)")
                }
            }
            .store(in: &c)

        $hasShadow
            .combineLatest($hasBorder)
            .map { hasShadow, hasBorder in
                hasShadow || hasBorder
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                guard let self else {
                    return
                }
                if shouldShow {
                    backingPanel.show(fadeIn: true)
                } else {
                    backingPanel.hide()
                }
            }
            .store(in: &c)

        $tintKind
            .map { tintKind in
                tintKind != .none
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                guard let self else {
                    return
                }
                if shouldShow {
                    overlayPanel.show(fadeIn: true)
                } else {
                    overlayPanel.hide()
                }
            }
            .store(in: &c)

        $tintGradient
            .receive(on: DispatchQueue.main)
            .encode(encoder: JSONEncoder())
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.menuBar.error("Error encoding tint gradient: \(error)")
                }
            } receiveValue: { data in
                UserDefaults.standard.set(data, forKey: Defaults.menuBarTintGradient)
            }
            .store(in: &c)

        $publishesAverageColor
            .sink { [weak self] publishesAverageColor in
                guard let self else {
                    return
                }
                // immediately update the average color
                if publishesAverageColor {
                    readAndUpdateAverageColor()
                } else {
                    averageColor = nil
                }
            }
            .store(in: &c)

        // propagate changes up from child observable objects
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

    private func readAndUpdateAverageColor() {
        let content = SharedContent.current

        guard
            let wallpaperWindow = content.firstWindow(where: .isWallpaperWindow),
            let menuBarWindow = content.firstWindow(where: .isMenuBarWindow),
            let image = WindowCaptureManager.captureImage(
                window: wallpaperWindow,
                captureRect: menuBarWindow.frame,
                options: .ignoreFraming
            ),
            let color = image.averageColor(
                accuracy: .low,
                algorithm: .simple,
                options: .ignoreAlpha
            )
        else {
            return
        }

        if averageColor != color {
            averageColor = color
        }
    }
}

// MARK: MenuBar: BindingExposable
extension MenuBar: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBar = mainSubsystem(category: "MenuBar")
}
