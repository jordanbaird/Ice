//
//  StatusBar.swift
//  Ice
//

import Combine
import OSLog

/// Manager for the state of items in the status bar.
class StatusBar: ObservableObject {
    private let encoder = DictionaryEncoder()

    private let decoder = DictionaryDecoder()

    private var cancellables = Set<AnyCancellable>()

    /// Combined hash of the most recently saved sections.
    private var lastSavedHash: Int?

    /// Set to `true` to tell the status bar to save its sections.
    @Published var needsSave = false

    /// The sections currently in the status bar.
    private(set) var sections = [StatusBarSection]() {
        willSet {
            for section in sections {
                section.statusBar = nil
            }
        }
        didSet {
            if validateSectionCount() {
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

    /// Performs the initial setup of the status bar's control item list.
    func initializeSections() {
        defer {
            if lastSavedHash == nil {
                lastSavedHash = sections.hashValue
            }
        }

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
        if
            let lastSavedHash,
            sections.hashValue == lastSavedHash
        {
            // items haven't changed, no need to save
            needsSave = false
            return
        }
        do {
            let serializedSections = try sections.map { section in
                try encoder.encode(section)
            }
            UserDefaults.standard.set(serializedSections, forKey: "Sections")
            lastSavedHash = sections.hashValue
            needsSave = false
        } catch {
            Logger.statusBar.error("Error encoding control item: \(error)")
        }
    }

    /// Performs validation on the current section count, reinitializing
    /// the sections if needed.
    ///
    /// - Returns: A Boolean value indicating whether the count was valid.
    private func validateSectionCount() -> Bool {
        if sections.count != 3 {
            sections = [
                StatusBarSection(
                    name: .alwaysVisible,
                    controlItem: ControlItem(autosaveName: "Item-1", position: 0)
                ),
                StatusBarSection(
                    name: .hidden,
                    controlItem: ControlItem(autosaveName: "Item-2", position: 1)
                ),
                // don't give the always-hidden item an initial position;
                // this will place it at the far end of the status bar
                StatusBarSection(
                    name: .alwaysHidden,
                    controlItem: ControlItem(autosaveName: "Item-3", position: nil)
                ),
            ]
            return false
        }
        return true
    }

    /// Set up a series of cancellables to respond to important changes
    /// in the status bar's state.
    private func configureCancellables() {
        // cancel and remove all current cancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        // update all control items when the position of one changes
        Publishers.MergeMany(sections.map { $0.controlItem.$position })
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                // expanded control items should preserve their ordering
                let sortedControlItems = sections.lazy
                    .map { section in
                        section.controlItem
                    }
                    .sorted { first, second in
                        switch (first.state, first.expandsOnHide, second.state, second.expandsOnHide) {
                        case (.showItems, _, .showItems, _):
                            return (first.position ?? 0) < (second.position ?? 0)
                        case (.hideItems, let expandsOnHide, _, _):
                            return !expandsOnHide
                        case (_, _, .hideItems, let expandsOnHide):
                            return expandsOnHide
                        }
                    }
                for index in 0..<sections.count {
                    sections[index].controlItem = sortedControlItems[index]
                }
            }
            .store(in: &cancellables)

        // save control items when a flag is set, avoiding rapid resaves
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
        return sections.first { $0.name == name }
    }
}
