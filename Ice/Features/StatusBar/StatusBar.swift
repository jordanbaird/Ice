//
//  StatusBar.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

class StatusBar {
    static let shared = StatusBar()

    private let list = ControlItemList()

    /// The current control items, unsorted.
    var controlItems: [ControlItem] {
        list.controlItems
    }

    /// The current control items, sorted by their position in the status bar.
    var sortedControlItems: [ControlItem] {
        controlItems.sorted {
            ($0.position ?? 0) < ($1.position ?? 0)
        }
    }

    /// Set to `true` to tell the status bar to save its control items.
    var needsSaveControlItems: Bool {
        get { list.needsSaveControlItems }
        set { list.needsSaveControlItems = newValue }
    }

    /// Shared menu to show when a control item is right-clicked.
    let menu: NSMenu = {
        let quitItem = NSMenuItem(title: "Quit Ice", action: #selector(NSApp.terminate), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]

        let menu = NSMenu(title: "Ice")
        menu.addItem(.separator())
        menu.addItem(quitItem)

        return menu
    }()

    private init() { }

    /// Performs the initial setup of the status bar's control item list.
    func initializeControlItems() {
        list.initializeControlItems(for: self)
    }

    /// Returns the status bar section for the given control item.
    func section(for controlItem: ControlItem) -> StatusBarSection? {
        sortedControlItems.enumerated().first { $0.element == controlItem }.flatMap { pair in
            StatusBarSection(rawValue: pair.offset)
        }
    }

    /// Returns the control item for the given section of the status bar.
    func controlItem(forSection section: StatusBarSection) -> ControlItem? {
        let index = section.rawValue
        guard index < controlItems.count else {
            return nil
        }
        return sortedControlItems[index]
    }
}

// MARK: - StatusBarSection

/// A representation of a section in a status bar.
enum StatusBarSection: Int {
    case alwaysVisible
    case hidden
    case alwaysHidden
}

// MARK: - ControlItemList

/// Observable list of control items.
private class ControlItemList: ObservableObject {
    private var saveCancellable: AnyCancellable?

    private var updateCancellable: AnyCancellable?

    private var lastSavedControlItemsHash: Int?

    @Published var needsSaveControlItems = false

    weak var statusBar: StatusBar? {
        didSet {
            setStatusBar(statusBar, for: controlItems)
        }
    }

    var controlItems = [ControlItem]() {
        willSet {
            setStatusBar(nil, for: controlItems)
            updateCancellable?.cancel()
        }
        didSet {
            if validateControlItemCount() {
                setStatusBar(statusBar, for: controlItems)
                updateCancellable = Publishers.MergeMany(controlItems.map { $0.$position })
                    .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                    .sink { [weak self] _ in
                        guard let self else {
                            return
                        }
                        for controlItem in controlItems {
                            controlItem.updateStatusItem()
                        }
                    }
                saveControlItems()
            }
        }
    }

    init() {
        self.saveCancellable = $needsSaveControlItems
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveControlItems()
                }
            }
    }

    func initializeControlItems(for statusBar: StatusBar) {
        guard controlItems.isEmpty else {
            return
        }

        if self.statusBar == nil {
            self.statusBar = statusBar
        }

        controlItems = Defaults.serializedControlItems.enumerated().map { index, entry in
            do {
                let dictionary = [entry.key: entry.value]
                return try DictionarySerialization.value(ofType: ControlItem.self, from: dictionary)
            } catch {
                Logger.statusBar.error("Error decoding control item: \(error)")
                return ControlItem(autosaveName: entry.key, position: CGFloat(index))
            }
        }
    }

    func saveControlItems() {
        if
            let lastSavedControlItemsHash,
            controlItems.hashValue == lastSavedControlItemsHash
        {
            // control items haven't changed; no need to save
            needsSaveControlItems = false
            return
        }
        do {
            Defaults.serializedControlItems = try controlItems.reduce(into: [:]) { serialized, item in
                let dictionary = try DictionarySerialization.dictionary(from: item)
                serialized.merge(dictionary, uniquingKeysWith: { $1 })
            }
            lastSavedControlItemsHash = controlItems.hashValue
            needsSaveControlItems = false
        } catch {
            Logger.statusBar.error("Error encoding control item: \(error)")
        }
    }

    /// Sets the given status bar for each of the given control items.
    private func setStatusBar(_ statusBar: StatusBar?, for controlItems: [ControlItem]) {
        for controlItem in controlItems {
            controlItem.statusBar = statusBar
        }
    }

    /// Performs validation on the current control item count, adding or
    /// removing items as needed, and returns a Boolean value indicating
    /// whether the count was valid.
    private func validateControlItemCount() -> Bool {
        let enableAlwaysHidden = Defaults.enableAlwaysHidden
        if controlItems.isEmpty {
            // fast path; don't do work if we don't have to
            var items = [
                ControlItem(position: 0),
                ControlItem(position: 1),
            ]
            if enableAlwaysHidden {
                items.append(ControlItem())
            }
            controlItems = items
            return false // count was invalid
        }
        // expected count varies based on whether the user has enabled
        // the always-hidden section
        let expectedCount = enableAlwaysHidden ? 3 : 2
        let actualCount = controlItems.count
        if actualCount == expectedCount {
            // count is already valid, so no need to do anything more
            return true
        }
        if actualCount < expectedCount {
            // add new items up to the expected count
            if enableAlwaysHidden {
                // subtract 1 from expected count and handle always-hidden
                // item separately
                controlItems += {
                    var items = (actualCount..<(expectedCount - 1)).map { index in
                        ControlItem(position: CGFloat(index))
                    }
                    // don't assign an initial position so that the item gets
                    // placed at the far end of the status bar
                    items.append(ControlItem())
                    return items
                }()
            } else {
                // always-hidden section is disabled, so don't worry about
                // separate handling
                controlItems += (actualCount..<expectedCount).map { index in
                    ControlItem(position: CGFloat(index))
                }
            }
        } else if actualCount > expectedCount {
            // remove extra items down to the expected count
            controlItems = Array(controlItems[..<expectedCount])
        }
        // if we made it this far, count was invalid
        return false
    }
}
