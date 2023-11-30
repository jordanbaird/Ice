//
//  MenuBar.swift
//  Ice
//

import AXSwift
import Combine
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
final class MenuBar: ObservableObject {
    /// The color of the menu bar's border.
    @Published var borderColor: CGColor = .black

    /// The width of the menu bar's border.
    @Published var borderWidth: Double = 1

    /// A Boolean value that indicates whether custom Ice icons
    /// should be rendered as template images.
    @Published var customIceIconIsTemplate = false

    /// A Boolean value that indicates whether the menu bar should
    /// have a border.
    @Published var hasBorder: Bool = false

    /// A Boolean value that indicates whether the menu bar should
    /// have a shadow.
    @Published var hasShadow: Bool = false

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var iceIcon: ControlItemImageSet = .defaultIceIcon

    /// The last user-selected custom Ice icon.
    @Published var lastCustomIceIcon: ControlItemImageSet?

    /// The maximum X coordinate of the menu bar's main menu.
    @Published var mainMenuMaxX: CGFloat = 0

    /// Set to `true` to tell the menu bar to save its sections.
    @Published var needsSave = false

    /// The modifier that triggers the secondary action on the
    /// menu bar's control items.
    @Published var secondaryActionModifier = Hotkey.Modifiers.option

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the user has interacted
    /// with the menu bar, preventing the "show on hover" feature from
    /// activating.
    @Published var showOnHoverPreventedByUserInteraction = false

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor = .black

    /// The user's currently chosen tint gradient.
    @Published var tintGradient: CustomGradient = .defaultMenuBarTint

    /// The tint kind currently in use.
    @Published var tintKind: MenuBarTintKind = .none

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

    private var cancellables = Set<AnyCancellable>()

    private weak var appState: AppState?
    private lazy var backingPanel = MenuBarBackingPanel(menuBar: self)
    private lazy var overlayPanel = MenuBarOverlayPanel(menuBar: self)

    private lazy var showOnHoverMonitor = UniversalEventMonitor(
        mask: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
        guard
            let self,
            !showOnHoverPreventedByUserInteraction
        else {
            return event
        }

        let locationOnScreen = event.locationOnScreen

        guard
            let screen = NSScreen.screens.first(where: { ($0.frame.minX...$0.frame.maxX).contains(locationOnScreen.x) }),
            let hiddenSection = section(withName: .hidden)
        else {
            return event
        }

        var mouseIsInMenuBar: Bool {
            guard let hiddenControlItemPosition = hiddenSection.controlItem.position else {
                return false
            }
            return locationOnScreen.y > screen.visibleFrame.maxY &&
            locationOnScreen.x > mainMenuMaxX &&
            screen.frame.maxX - locationOnScreen.x > hiddenControlItemPosition
        }

        switch event.type {
        case .mouseMoved:
            if hiddenSection.isHidden {
                if mouseIsInMenuBar {
                    hiddenSection.show()
                }
            } else {
                if locationOnScreen.y < screen.visibleFrame.maxY {
                    hiddenSection.hide()
                }
            }
        case .leftMouseDown:
            guard
                let visibleSection = section(withName: .visible),
                let visibleControlItemFrame = visibleSection.controlItem.windowFrame
            else {
                break
            }
            if mouseIsInMenuBar || visibleControlItemFrame.contains(locationOnScreen) {
                showOnHoverPreventedByUserInteraction = true
            }
        case .rightMouseDown, .otherMouseDown:
            if mouseIsInMenuBar {
                showOnHoverPreventedByUserInteraction = true
            }
        default:
            break
        }

        return event
    }

    /// Initializes a new menu bar instance.
    init(appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads data from storage and sets the initial state of the
    /// menu bar from that data.
    private func loadInitialState() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        hasShadow = defaults.bool(forKey: Defaults.menuBarHasShadow)
        hasBorder = defaults.bool(forKey: Defaults.menuBarHasBorder)
        borderWidth = defaults.object(forKey: Defaults.menuBarBorderWidth) as? Double ?? 1
        tintKind = MenuBarTintKind(rawValue: defaults.integer(forKey: Defaults.menuBarTintKind)) ?? .none
        customIceIconIsTemplate = defaults.bool(forKey: Defaults.customIceIconIsTemplate)
        showOnHover = defaults.bool(forKey: Defaults.showOnHover)

        do {
            if let borderColorData = defaults.data(forKey: Defaults.menuBarBorderColor) {
                borderColor = try decoder.decode(CodableColor.self, from: borderColorData).cgColor
            }
            if let tintColorData = defaults.data(forKey: Defaults.menuBarTintColor) {
                tintColor = try decoder.decode(CodableColor.self, from: tintColorData).cgColor
            }
            if let tintGradientData = defaults.data(forKey: Defaults.menuBarTintGradient) {
                tintGradient = try decoder.decode(CustomGradient.self, from: tintGradientData)
            }
            if let iceIconData = defaults.data(forKey: Defaults.iceIcon) {
                iceIcon = try decoder.decode(ControlItemImageSet.self, from: iceIconData)
                if case .custom = iceIcon.name {
                    lastCustomIceIcon = iceIcon
                }
            }
            if let modifierRawValue = defaults.object(forKey: Defaults.secondaryActionModifier) as? Int {
                secondaryActionModifier = Hotkey.Modifiers(rawValue: modifierRawValue)
            }
        } catch {
            Logger.menuBar.error("Error decoding value: \(error)")
        }
    }

    /// Performs the initial setup of the menu bar's section list.
    func initializeSections() {
        guard sections.isEmpty else {
            Logger.menuBar.info("Sections already initialized")
            return
        }

        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        // load sections from persistent storage
        if let sectionsData = defaults.data(forKey: Defaults.sections) {
            do {
                sections = try decoder.decode([MenuBarSection].self, from: sectionsData)
            } catch {
                Logger.menuBar.error("Decoding error: \(error)")
                sections = []
            }
        } else {
            sections = []
        }
    }

    /// Save all control items in the menu bar to persistent storage.
    func saveSections() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()

        do {
            let serializedSections = try encoder.encode(sections)
            defaults.set(serializedSections, forKey: Defaults.sections)
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
                MenuBarSection(name: .visible),
                MenuBarSection(name: .hidden),
                MenuBarSection(name: .alwaysHidden),
            ]
            return false
        }
        return true
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()

        // update the maxX coordinate of the main menu every
        // time the application that owns the menu bar changes
        NSWorkspace.shared.publisher(for: \.menuBarOwningApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningApplication in
                guard let self else {
                    return
                }
                do {
                    guard
                        let runningApplication,
                        let application = Application(runningApplication),
                        let menuBar: UIElement = try application.attribute(.menuBar),
                        let children: [UIElement] = try menuBar.arrayAttribute(.children),
                        let maxX = try children.compactMap({ try ($0.attribute(.frame) as CGRect?)?.maxX }).max()
                    else {
                        mainMenuMaxX = 0
                        return
                    }
                    mainMenuMaxX = maxX
                } catch {
                    mainMenuMaxX = 0
                    Logger.menuBar.error("Error updating main menu maxX: \(error)")
                }
            }
            .store(in: &c)

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

        $hasShadow
            .receive(on: DispatchQueue.main)
            .sink { hasShadow in
                defaults.set(hasShadow, forKey: Defaults.menuBarHasShadow)
            }
            .store(in: &c)

        $hasBorder
            .receive(on: DispatchQueue.main)
            .sink { hasBorder in
                defaults.set(hasBorder, forKey: Defaults.menuBarHasBorder)
            }
            .store(in: &c)

        $borderColor
            .receive(on: DispatchQueue.main)
            .sink { borderColor in
                do {
                    let data = try encoder.encode(CodableColor(cgColor: borderColor))
                    defaults.set(data, forKey: Defaults.menuBarBorderColor)
                } catch {
                    Logger.menuBar.error("Error encoding border color: \(error)")
                }
            }
            .store(in: &c)

        $borderWidth
            .receive(on: DispatchQueue.main)
            .sink { borderWidth in
                defaults.set(borderWidth, forKey: Defaults.menuBarBorderWidth)
            }
            .store(in: &c)

        $tintKind
            .receive(on: DispatchQueue.main)
            .sink { tintKind in
                defaults.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
            }
            .store(in: &c)

        $tintColor
            .receive(on: DispatchQueue.main)
            .sink { tintColor in
                do {
                    let data = try encoder.encode(CodableColor(cgColor: tintColor))
                    defaults.set(data, forKey: Defaults.menuBarTintColor)
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
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.menuBar.error("Error encoding tint gradient: \(error)")
                }
            } receiveValue: { data in
                defaults.set(data, forKey: Defaults.menuBarTintGradient)
            }
            .store(in: &c)

        $iceIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iceIcon in
                guard let self else {
                    return
                }
                if case .custom = iceIcon.name {
                    lastCustomIceIcon = iceIcon
                }
                do {
                    let data = try encoder.encode(iceIcon)
                    defaults.set(data, forKey: Defaults.iceIcon)
                } catch {
                    Logger.menuBar.error("Error encoding Ice icon: \(error)")
                }
            }
            .store(in: &c)

        $customIceIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { isTemplate in
                defaults.set(isTemplate, forKey: Defaults.customIceIconIsTemplate)
            }
            .store(in: &c)

        $secondaryActionModifier
            .receive(on: DispatchQueue.main)
            .sink { modifier in
                defaults.set(modifier.rawValue, forKey: Defaults.secondaryActionModifier)
            }
            .store(in: &c)

        $showOnHover
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showOnHover in
                if showOnHover {
                    self?.showOnHoverMonitor.start()
                } else {
                    self?.showOnHoverMonitor.stop()
                }
                defaults.set(showOnHover, forKey: Defaults.showOnHover)
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
}

// MARK: MenuBar: BindingExposable
extension MenuBar: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBar = Logger(category: "MenuBar")
}
