//
//  MenuBar.swift
//  Ice
//

import Combine
import OSLog

/// Manager for the state of items in the menu bar.
class MenuBar: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private let encoder = DictionaryEncoder()
    private let decoder = DictionaryDecoder()

    let sharedContent = SharedContent(maxInterval: 1, queue: .global(qos: .utility))
    private(set) lazy var colorReader = MenuBarColorReader(menuBar: self)
    private(set) lazy var itemManager = MenuBarItemManager(menuBar: self)

    /// Set to `true` to tell the menu bar to save its sections.
    @Published var needsSave = false

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

    /// Initializes a new menu bar instance.
    init() {
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
                return try decoder.decode(MenuBarSection.self, from: dictionary)
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
                try encoder.encode(section)
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

    /// Sets up a series of cancellables to respond to changes in the
    /// menu bar's state.
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

        // save sections when needsSave is set to true, debounced
        // to a reasonable timeframe
        $needsSave
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveSections()
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
        colorReader.objectWillChange
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
}

// MARK: - Logger
extension Logger {
    static let menuBar = mainSubsystem(category: "MenuBar")
}
