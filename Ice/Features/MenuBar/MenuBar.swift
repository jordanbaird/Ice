//
//  MenuBar.swift
//  Ice
//

import Combine
import OSLog

/// Manager for the state of items in the menu bar.
class MenuBar: ObservableObject {
    /// Observers for important aspects of state.
    private var cancellables = Set<AnyCancellable>()

    /// Encoder for serialization of Codable objects into
    /// a dictionary format.
    private let encoder = DictionaryEncoder()

    /// Decoder for deserialization of dictionaries into
    /// Codable objects.
    private let decoder = DictionaryDecoder()

    /// A manager for the items in the menu bar.
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
                MenuBarSection(name: .alwaysVisible, autosaveName: "Item-1", position: 0),
                MenuBarSection(name: .hidden, autosaveName: "Item-2", position: 1),
                // don't give the always-hidden section an initial position,
                // so that its item is placed at the far end of the menu bar
                MenuBarSection(name: .alwaysHidden, autosaveName: "Item-3", state: .hideItems),
            ]
            return false
        }
        return true
    }

    /// Sets up a series of cancellables to respond to important
    /// changes in the menu bar's state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // update the control item for every section when the
        // position of one item changes
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

        // save control items when needsSave is set to true,
        // debounced to avoid saving too often
        $needsSave
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveSections()
                }
            }
            .store(in: &c)

        itemManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        // propagate changes up from each section
        for section in sections {
            section.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
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
