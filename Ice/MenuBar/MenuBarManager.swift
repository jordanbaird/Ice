//
//  MenuBarManager.swift
//  Ice
//

import AXSwift
import Combine
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
final class MenuBarManager: ObservableObject {
    /// Set to `true` to tell the menu bar to save its sections.
    @Published var needsSave = false

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var iceIcon: ControlItemImageSet = .defaultIceIcon

    /// A Boolean value that indicates whether custom Ice icons
    /// should be rendered as template images.
    @Published var customIceIconIsTemplate = false

    /// The last user-selected custom Ice icon.
    @Published var lastCustomIceIcon: ControlItemImageSet?

    /// The modifier that triggers the secondary action on the
    /// menu bar's control items.
    @Published var secondaryActionModifier: Hotkey.Modifiers = .option

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the user has
    /// interacted with the menu bar, preventing the "show on
    /// hover" feature from activating.
    @Published var showOnHoverPreventedByUserInteraction = false

    /// The maximum X coordinate of the menu bar's main menu.
    @Published var mainMenuMaxX: CGFloat = 0

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

    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let defaults = UserDefaults.standard

    private(set) weak var appState: AppState?
    private(set) lazy var appearanceManager = MenuBarAppearanceManager(
        menuBarManager: self,
        encoder: encoder,
        decoder: decoder
    )

    private lazy var showOnHoverMonitor = UniversalEventMonitor(
        mask: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
        guard
            let self,
            !showOnHoverPreventedByUserInteraction
        else {
            return event
        }

        guard
            let screen = NSScreen.screens.first(where: {
                ($0.frame.minX...$0.frame.maxX).contains(NSEvent.mouseLocation.x)
            }),
            let hiddenSection = section(withName: .hidden)
        else {
            return event
        }

        var mouseIsInMenuBar: Bool {
            guard let hiddenControlItemPosition = hiddenSection.controlItem.position else {
                return false
            }
            return NSEvent.mouseLocation.y > screen.visibleFrame.maxY &&
            NSEvent.mouseLocation.x > mainMenuMaxX &&
            screen.frame.maxX - NSEvent.mouseLocation.x > hiddenControlItemPosition
        }

        switch event.type {
        case .mouseMoved where hiddenSection.isHidden:
            if mouseIsInMenuBar {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // make sure the mouse is still inside
                    if mouseIsInMenuBar {
                        hiddenSection.show()
                    }
                }
            }
        case .mouseMoved:
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // make sure the mouse is still outside
                    if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                        hiddenSection.hide()
                    }
                }
            }
        case .leftMouseDown:
            guard
                let visibleSection = section(withName: .visible),
                let visibleControlItemFrame = visibleSection.controlItem.windowFrame
            else {
                break
            }
            if mouseIsInMenuBar || visibleControlItemFrame.contains(NSEvent.mouseLocation) {
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

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Performs the initial setup of the menu bar.
    func performSetup() {
        defer {
            appearanceManager.performSetup()
        }
        loadInitialState()
        configureCancellables()
        initializeSections()
    }

    /// Loads data from storage and sets the initial state
    /// of the menu bar from that data.
    private func loadInitialState() {
        customIceIconIsTemplate = defaults.bool(forKey: Defaults.customIceIconIsTemplate)
        showOnHover = defaults.bool(forKey: Defaults.showOnHover)

        do {
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
            Logger.menuBarManager.error("Error decoding value: \(error)")
        }
    }

    /// Performs the initial setup of the menu bar's section list.
    private func initializeSections() {
        guard sections.isEmpty else {
            Logger.menuBarManager.info("Sections already initialized")
            return
        }

        // load sections from persistent storage
        if let sectionsData = defaults.data(forKey: Defaults.sections) {
            do {
                sections = try decoder.decode([MenuBarSection].self, from: sectionsData)
            } catch {
                Logger.menuBarManager.error("Decoding error: \(error)")
                sections = []
            }
        } else {
            sections = []
        }
    }

    /// Save all control items in the menu bar to persistent storage.
    private func saveSections() {
        do {
            let serializedSections = try encoder.encode(sections)
            defaults.set(serializedSections, forKey: Defaults.sections)
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

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .sink { [weak self] frontmostApplication in
                self?.handleFrontmostApplication(frontmostApplication)
            }
            .store(in: &c)

        Publishers.MergeMany(sections.map { $0.controlItem.$position })
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.assignControlItemsByPosition()
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
                    Logger.menuBarManager.error("Error encoding Ice icon: \(error)")
                }
            }
            .store(in: &c)

        $customIceIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTemplate in
                self?.defaults.set(isTemplate, forKey: Defaults.customIceIconIsTemplate)
            }
            .store(in: &c)

        $secondaryActionModifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modifier in
                self?.defaults.set(modifier.rawValue, forKey: Defaults.secondaryActionModifier)
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
                self?.defaults.set(showOnHover, forKey: Defaults.showOnHover)
            }
            .store(in: &c)

        // propagate changes up from child observable objects
        appearanceManager.objectWillChange
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

    /// Handles changes to the frontmost application.
    private func handleFrontmostApplication(_ frontmostApplication: NSRunningApplication?) {
        guard let frontmostApplication else {
            return
        }

        let appID = frontmostApplication.localizedName ?? "PID \(frontmostApplication.processIdentifier)"
        Logger.menuBarManager.debug("New frontmost application: \(appID)")

        // wait until the application is finished launching
        var box: BoxObject<AnyCancellable?>? = BoxObject()
        box?.base = frontmostApplication.publisher(for: \.isFinishedLaunching)
            .combineLatest(frontmostApplication.publisher(for: \.ownsMenuBar))
            .sink { [weak self] isFinishedLaunching, ownsMenuBar in
                // Ice never actually owns the menu bar, so exclude it from the check
                if frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    guard ownsMenuBar else {
                        Logger.menuBarManager.debug("\(appID) does not own menu bar")
                        return
                    }
                }
                guard isFinishedLaunching else {
                    Logger.menuBarManager.debug("\(appID) is launching...")
                    return
                }

                Logger.menuBarManager.debug("\(appID) is finished launching")

                defer {
                    box = nil
                }

                guard let self else {
                    return
                }

                do {
                    // get the largest x-coordinate of all items
                    guard
                        let application = Application(frontmostApplication),
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
                    Logger.menuBarManager.error("Error updating main menu maxX: \(error)")
                }
            }
    }

    /// Updates the control item for each section based on the
    /// current control item positions.
    private func assignControlItemsByPosition() {
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
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
