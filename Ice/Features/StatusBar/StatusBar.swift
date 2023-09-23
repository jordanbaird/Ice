//
//  StatusBar.swift
//  Ice
//

import Combine
import OSLog

/// Manager for the state of items in the status bar.
class StatusBar: ObservableObject {
    /// Observers for important aspects of state.
    private var cancellables = Set<AnyCancellable>()

    /// Encoder for serialization of Codable objects into
    /// a dictionary format.
    private let encoder = DictionaryEncoder()

    /// Decoder for deserialization of dictionaries into
    /// Codable objects.
    private let decoder = DictionaryDecoder()

    /// Set to `true` to tell the status bar to save its sections.
    @Published var needsSave = false

    /// The sections currently in the status bar.
    @Published private(set) var sections = [StatusBarSection]() {
        willSet {
            for section in sections {
                section.statusBar = nil
            }
        }
        didSet {
            if validateSectionCountOrReinitialize() {
                for section in sections {
                    section.statusBar = self
                }
            }
            configureCancellables()
            needsSave = true
        }
    }

    /// Initializes a new status bar instance.
    init() {
        configureCancellables()
    }

    /// Performs the initial setup of the status bar's section list.
    func initializeSections() {
        guard sections.isEmpty else {
            Logger.statusBar.info("Sections already initialized")
            return
        }

        // load sections from persistent storage
        sections = (UserDefaults.standard.array(forKey: "Sections") ?? []).compactMap { entry in
            guard let dictionary = entry as? [String: Any] else {
                Logger.statusBar.error("Entry not convertible to dictionary")
                return nil
            }
            do {
                return try decoder.decode(StatusBarSection.self, from: dictionary)
            } catch {
                Logger.statusBar.error("Error decoding control item: \(error)")
                return nil
            }
        }
    }

    /// Save all control items in the status bar to persistent storage.
    func saveSections() {
        do {
            let serializedSections = try sections.map { section in
                try encoder.encode(section)
            }
            UserDefaults.standard.set(serializedSections, forKey: "Sections")
            needsSave = false
        } catch {
            Logger.statusBar.error("Error encoding control item: \(error)")
        }
    }

    /// Performs validation on the current section count, reinitializing
    /// the sections if needed.
    ///
    /// - Returns: A Boolean value indicating whether the count was valid.
    private func validateSectionCountOrReinitialize() -> Bool {
        if sections.count != 3 {
            sections = [
                StatusBarSection(name: .alwaysVisible, autosaveName: "Item-1", position: 0),
                StatusBarSection(name: .hidden, autosaveName: "Item-2", position: 1),
                // don't give the always-hidden section an initial position; 
                // this will place its item at the far end of the status bar
                StatusBarSection(name: .alwaysHidden, autosaveName: "Item-3", state: .hideItems),
            ]
            return false
        }
        return true
    }

    /// Set up a series of cancellables to respond to important 
    /// changes in the status bar's state.
    private func configureCancellables() {
        // cancel and remove all current cancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

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
            .store(in: &cancellables)

        // save control items when needsSave is set to true, 
        // with a reasonable delay to avoid saving too often
        $needsSave
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveSections()
                }
            }
            .store(in: &cancellables)

        // propagate changes up from each section
        for section in sections {
            section.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        }
    }

    /// Returns the status bar section with the given name.
    func section(withName name: StatusBarSection.Name) -> StatusBarSection? {
        sections.first { $0.name == name }
    }
}
