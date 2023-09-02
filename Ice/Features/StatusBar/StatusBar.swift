//
//  StatusBar.swift
//  Ice
//

import Combine
import OSLog
import SwiftKeys

/// Manager for the state of items in the status bar.
class StatusBar: ObservableObject {
    private let encoder = DictionaryEncoder()
    private let decoder = DictionaryDecoder()

    private var cancellables = Set<AnyCancellable>()
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

    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    var isAlwaysHiddenSectionEnabled: Bool {
        get { section(withName: .alwaysHidden)?.controlItem.isVisible ?? false }
        set { section(withName: .alwaysHidden)?.controlItem.isVisible = newValue }
    }

    init() {
        configureCancellables()
        configureKeyCommands(for: [.hidden, .alwaysHidden])
    }

    /// Performs the initial setup of the status bar's control item list.
    func initializeSections() {
        defer {
            if lastSavedHash == nil {
                lastSavedHash = sections.hashValue
            }
        }

        guard sections.isEmpty else {
            return
        }

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
                    controlItem: ControlItem(position: 0)
                ),
                StatusBarSection(
                    name: .hidden,
                    controlItem: ControlItem(position: 1)
                ),
                // don't give the always-hidden item an initial position;
                // this will place it at the far end of the status bar
                StatusBarSection(
                    name: .alwaysHidden,
                    controlItem: ControlItem()
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
                        switch (first.state, second.state) {
                        case (.showItems, .showItems):
                            return (first.position ?? 0) < (second.position ?? 0)
                        case (.hideItems(let isExpanded), _):
                            return !isExpanded
                        case (_, .hideItems(let isExpanded)):
                            return isExpanded
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
    }

    /// Set up key commands for the sections with the given names.
    private func configureKeyCommands(for sectionNames: [StatusBarSection.Name]) {
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        for name in sectionNames {
            let keyCommand = KeyCommand(name: .toggleSection(withName: name))
            keyCommand.disablesOnMenuOpen = true
            keyCommand.observe(.keyDown) { [weak self] in
                self?.toggleSection(withName: name)
            }
        }
    }

    /// Returns the status bar section with the given name.
    func section(withName name: StatusBarSection.Name) -> StatusBarSection? {
        return sections.first { $0.name == name }
    }

    /// Returns the status bar section for the given control item.
    func section(for controlItem: ControlItem) -> StatusBarSection? {
        guard controlItem.isVisible else {
            return nil
        }
        return sections.first { $0.controlItem == controlItem }
    }

    /// Returns the status bar section after the given section.
    func section(after other: StatusBarSection) -> StatusBarSection? {
        guard let index = sections.firstIndex(of: other) else {
            return nil
        }
        let nextIndex = sections.index(after: index)
        guard sections.indices.contains(nextIndex) else {
            return nil
        }
        return sections[nextIndex]
    }

    /// Returns the status bar section before the given section.
    func section(before other: StatusBarSection) -> StatusBarSection? {
        guard let index = sections.firstIndex(of: other) else {
            return nil
        }
        let previousIndex = sections.index(before: index)
        guard sections.indices.contains(previousIndex) else {
            return nil
        }
        return sections[previousIndex]
    }

    /// Returns a Boolean value that indicates whether the given section
    /// is hidden by its control item.
    func isSectionHidden(_ section: StatusBarSection) -> Bool {
        switch section.controlItem.state {
        case .hideItems: return true
        case .showItems: return false
        }
    }

    /// Returns a Boolean value that indicates whether the control item
    /// for the given section is currently visible.
    func isSectionEnabled(_ section: StatusBarSection) -> Bool {
        return section.controlItem.isVisible
    }

    /// Shows the status items in the given section.
    func showSection(withName name: StatusBarSection.Name) {
        // FIXME: Make this work for more than just the currently defined sections.
        // The user should be able to define their own sections, and this function
        // needs to be able to support them.
        switch name {
        case .alwaysVisible, .hidden:
            section(withName: .alwaysVisible)?.controlItem.state = .showItems
            section(withName: .hidden)?.controlItem.state = .showItems
        case .alwaysHidden:
            showSection(withName: .hidden)
            section(withName: .alwaysHidden)?.controlItem.state = .showItems
        default:
            Logger.statusBar.warning("\(#function) is not implemented for section name \(name.rawValue)")
            break
        }
    }

    /// Hides the status items in the given section.
    func hideSection(withName name: StatusBarSection.Name) {
        // FIXME: Make this work for more than just the currently defined sections.
        // The user should be able to define their own sections, and this function
        // needs to be able to support them.
        switch name {
        case .alwaysVisible, .hidden:
            section(withName: .alwaysVisible)?.controlItem.state = .hideItems(isExpanded: false)
            section(withName: .hidden)?.controlItem.state = .hideItems(isExpanded: true)
            hideSection(withName: .alwaysHidden)
        case .alwaysHidden:
            section(withName: .alwaysHidden)?.controlItem.state = .hideItems(isExpanded: true)
        default:
            Logger.statusBar.warning("\(#function) is not implemented for section name \(name.rawValue)")
            break
        }
    }

    /// Toggles the visibility of the status items in the given section.
    func toggleSection(withName name: StatusBarSection.Name) {
        guard let section = section(withName: name) else {
            Logger.statusBar.warning("Missing section for name \(name.rawValue)")
            return
        }
        switch section.controlItem.state {
        case .hideItems:
            showSection(withName: section.name)
        case .showItems:
            hideSection(withName: section.name)
        }
    }
}
