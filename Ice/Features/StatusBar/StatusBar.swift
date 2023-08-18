//
//  StatusBar.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import SwiftKeys

/// Manager for the state of items in the status bar.
class StatusBar: ObservableObject {
    /// Representation of a section in the status bar.
    enum Section: Int {
        case alwaysVisible
        case hidden
        case alwaysHidden

        /// User-visible name that describes the section.
        var name: String {
            switch self {
            case .alwaysVisible: return "Always Visible"
            case .hidden: return "Hidden"
            case .alwaysHidden: return "Always Hidden"
            }
        }
    }

    private let encoder = DictionaryEncoder()
    private let decoder = DictionaryDecoder()

    private var cancellables = Set<AnyCancellable>()
    private var lastSavedControlItemsHash: Int?

    /// Set to `true` to tell the status bar to save its control items.
    @Published var needsSaveControlItems = false

    /// The current control items, unsorted.
    private(set) var controlItems = [ControlItem]() {
        willSet {
            for controlItem in controlItems {
                controlItem.statusBar = nil
            }
        }
        didSet {
            if validateControlItemCount() {
                for controlItem in controlItems {
                    controlItem.statusBar = self
                }
            }
            configureCancellables()
            needsSaveControlItems = true
        }
    }

    /// The current control items, sorted by their position in the status bar.
    var sortedControlItems: [ControlItem] {
        controlItems.sorted {
            ($0.position ?? 0) < ($1.position ?? 0)
        }
    }

    var isAlwaysHiddenSectionEnabled: Bool {
        get { controlItem(for: .alwaysHidden)?.isVisible ?? false }
        set { controlItem(for: .alwaysHidden)?.isVisible = newValue }
    }

    init() {
        configureCancellables()
        configureKeyCommands(for: [.hidden, .alwaysHidden])
    }

    /// Performs the initial setup of the status bar's control item list.
    func initializeControlItems() {
        defer {
            if lastSavedControlItemsHash == nil {
                lastSavedControlItemsHash = controlItems.hashValue
            }
        }

        guard controlItems.isEmpty else {
            return
        }

        controlItems = Defaults[.serializedControlItems].enumerated().map { index, entry in
            do {
                let dictionary = [entry.key: entry.value]
                return try decoder.decode(ControlItem.self, from: dictionary)
            } catch {
                Logger.statusBar.error("Error decoding control item: \(error)")
                return ControlItem(autosaveName: entry.key, position: CGFloat(index))
            }
        }
    }

    /// Save all control items in the status bar to persistent storage.
    func saveControlItems() {
        if
            let lastSavedControlItemsHash,
            controlItems.hashValue == lastSavedControlItemsHash
        {
            // items haven't changed, no need to save
            needsSaveControlItems = false
            return
        }
        do {
            Defaults[.serializedControlItems] = try controlItems.reduce(into: [:]) { serialized, item in
                try serialized.merge(encoder.encode(item), uniquingKeysWith: { $1 })
            }
            lastSavedControlItemsHash = controlItems.hashValue
            needsSaveControlItems = false
        } catch {
            Logger.statusBar.error("Error encoding control item: \(error)")
        }
    }

    /// Performs validation on the current control item count, adding or
    /// removing items as needed, and returns a Boolean value indicating
    /// whether the count was valid.
    private func validateControlItemCount() -> Bool {
        if controlItems.count != 3 {
            controlItems = [
                ControlItem(position: 0),
                ControlItem(position: 1),
                // don't give the always-hidden item an initial position;
                // this will place it at the far end of the status bar
                ControlItem(),
            ]
            return false // count was invalid
        }
        return true // count was valid
    }

    /// Set up a series of cancellables to respond to key changes in the
    /// status bar's state.
    private func configureCancellables() {
        // cancel and remove all current cancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        // update all control items when the position of one changes
        Publishers.MergeMany(controlItems.map { $0.$position })
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                for controlItem in controlItems {
                    controlItem.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        // save control items when a flag is set, avoiding rapid resaves
        $needsSaveControlItems
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveControlItems()
                }
            }
            .store(in: &cancellables)
    }

    /// Set up key commands (and their observations) for the given sections.
    private func configureKeyCommands(for sections: [Section]) {
        guard !ProcessInfo.processInfo.isPreview else {
            return
        }
        for section in sections {
            let keyCommand = KeyCommand(name: .toggle(section))
            keyCommand.disablesOnMenuOpen = true
            keyCommand.observe(.keyDown) { [weak self] in
                self?.toggle(section: section)
            }
        }
    }

    /// Returns the status bar section for the given control item.
    func section(for controlItem: ControlItem) -> Section? {
        guard controlItem.isVisible else {
            return nil
        }
        return sortedControlItems.enumerated().first { $0.element == controlItem }.flatMap { pair in
            Section(rawValue: pair.offset)
        }
    }

    /// Returns the control item for the given status bar section.
    func controlItem(for section: Section) -> ControlItem? {
        let index = section.rawValue
        guard index < controlItems.count else {
            return nil
        }
        return sortedControlItems[index]
    }

    /// Returns a Boolean value that indicates whether the given section
    /// is hidden by its control item.
    func isSectionHidden(_ section: Section) -> Bool {
        guard let item = controlItem(for: section) else {
            return false
        }
        switch item.state {
        case .hideItems: return true
        case .showItems: return false
        }
    }

    /// Returns a Boolean value that indicates whether the item for the
    /// given section is currently visible.
    func isSectionEnabled(_ section: Section) -> Bool {
        guard let item = controlItem(for: section) else {
            return false
        }
        return item.isVisible
    }

    /// Shows the status items in the given section.
    func show(section: Section) {
        switch section {
        case .alwaysVisible, .hidden:
            controlItem(for: .alwaysVisible)?.state = .showItems
            controlItem(for: .hidden)?.state = .showItems
        case .alwaysHidden:
            show(section: .hidden)
            controlItem(for: .alwaysHidden)?.state = .showItems
        }
    }

    /// Hides the status items in the given section.
    func hide(section: Section) {
        switch section {
        case .alwaysVisible, .hidden:
            controlItem(for: .alwaysVisible)?.state = .hideItems(isExpanded: false)
            controlItem(for: .hidden)?.state = .hideItems(isExpanded: true)
            hide(section: .alwaysHidden)
        case .alwaysHidden:
            controlItem(for: .alwaysHidden)?.state = .hideItems(isExpanded: true)
        }
    }

    /// Toggles the visibility of the status items in the given section.
    func toggle(section: Section) {
        guard let item = controlItem(for: section) else {
            return
        }
        switch item.state {
        case .hideItems:
            show(section: section)
        case .showItems:
            hide(section: section)
        }
    }
}
