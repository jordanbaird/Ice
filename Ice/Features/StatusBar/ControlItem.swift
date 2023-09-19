//
//  ControlItem.swift
//  Ice
//

import Cocoa
import Combine

/// A box around a status item that controls the visibility of a
/// status bar section.
final class ControlItem: ObservableObject {
    /// A value representing the hiding state of a control item.
    enum HidingState: RawRepresentable, Hashable, Codable {
        /// Status items in the control item's status bar section
        /// are hidden.
        case hideItems(isExpanded: Bool)
        /// Status items in the control item's status bar section
        /// are visible.
        case showItems

        var rawValue: Int {
            switch self {
            case .hideItems(isExpanded: false): 0
            case .hideItems(isExpanded: true): 1
            case .showItems: 2
            }
        }

        init?(rawValue: Int) {
            switch rawValue {
            case 0: self = .hideItems(isExpanded: false)
            case 1: self = .hideItems(isExpanded: true)
            case 2: self = .showItems
            default: return nil
            }
        }
    }

    /// The length of a control item that is not currently hiding
    /// its status bar section.
    static let standardLength: CGFloat = 25

    /// The length of a control item that is currently hiding its
    /// status bar section.
    static let expandedLength: CGFloat = 10_000

    private static let storage = ObjectAssociation<StatusBarSection>()

    /// The underlying status item associated with the control item.
    private let statusItem: NSStatusItem

    private var cancellables = Set<AnyCancellable>()

    /// The control item's autosave name.
    var autosaveName: String {
        statusItem.autosaveName
    }

    /// The status bar associated with the control item.
    weak var statusBar: StatusBar? {
        didSet {
            updateStatusItem()
        }
    }

    /// The status bar section associated with the control item.
    var section: StatusBarSection? {
        guard 
            isVisible,
            let statusBar
        else {
            return nil
        }
        return statusBar.sections.first { $0.controlItem == self }
    }

    /// The position of the control item in the status bar.
    @Published private(set) var position: CGFloat?

    /// A Boolean value that indicates whether the control
    /// item is visible.
    ///
    /// This value corresponds to whether the item's section
    /// is enabled.
    var isVisible: Bool {
        get {
            statusItem.isVisible
        }
        set {
            objectWillChange.send()
            let autosaveName = autosaveName
            let cached = PreferredPosition[autosaveName]
            defer {
                PreferredPosition[autosaveName] = cached
            }
            statusItem.isVisible = newValue
            statusBar?.needsSave = true
        }
    }

    /// The hiding state of the control item.
    ///
    /// Setting this value marks the item as needing an update.
    @Published var state: HidingState {
        didSet {
            updateStatusItem()
        }
    }

    /// Creates a control item with the given autosave name, position,
    /// and hiding state.
    ///
    /// - Parameters:
    ///   - autosaveName: The control item's autosave name.
    ///   - position: The position of the control item in the status bar.
    ///   - state: The hiding state of the control item.
    init(
        autosaveName: String,
        position: CGFloat?,
        state: HidingState? = nil
    ) {
        if let position {
            // set the preferred position first to ensure that
            // the status item appears in the correct position
            PreferredPosition[autosaveName] = position
        }
        self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
        self.statusItem.autosaveName = autosaveName
        self.position = position
        self.state = state ?? .showItems
        configureStatusItem()
    }

    /// Sets the initial configuration for the status item.
    private func configureStatusItem() {
        defer {
            configureCancellables()
            updateStatusItem()
        }
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(performAction)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    /// Set up a series of observers to respond to important changes
    /// in the control item's state.
    private func configureCancellables() {
        // cancel and remove all current cancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        if let window = statusItem.button?.window {
            window.publisher(for: \.frame)
                .combineLatest(window.publisher(for: \.screen))
                .compactMap { [weak statusItem] frame, screen in
                    // only publish when status item has a standard length and
                    // window is at least partially onscreen
                    guard
                        statusItem?.length == Self.standardLength,
                        let screenFrame = screen?.frame,
                        screenFrame.intersects(frame)
                    else {
                        return nil
                    }
                    // calculate position relative to trailing edge of screen
                    return screenFrame.maxX - frame.maxX
                }
                .removeDuplicates()
                .sink { [weak self] position in
                    self?.position = position
                }
                .store(in: &cancellables)
        }
    }

    /// Updates the control item's status item to match its current state.
    func updateStatusItem() {
        func updateLength(section: StatusBarSection) {
            if section.name == .alwaysVisible {
                // item for always-visible section should never be expanded
                statusItem.length = Self.standardLength
                return
            }
            switch state {
            case .showItems, .hideItems(isExpanded: false):
                statusItem.length = Self.standardLength
            case .hideItems(isExpanded: true):
                statusItem.length = Self.expandedLength
            }
        }

        func updateButton(section: StatusBarSection) {
            guard let button = statusItem.button else {
                return
            }
            if state == .hideItems(isExpanded: true) {
                // prevent the cell from highlighting while expanded
                button.cell?.isEnabled = false
                // cell still sometimes briefly flashes during expansion;
                // manually unhighlighting seems to mitigate it
                button.isHighlighted = false
                button.image = nil
                return
            }
            // enable the cell, as it may have been previously disabled
            button.cell?.isEnabled = true
            // set the image based on section and state
            switch section.name {
            case .hidden:
                button.image = ControlItemImages.largeChevron
            case .alwaysHidden:
                button.image = ControlItemImages.smallChevron
            case .alwaysVisible:
                switch state {
                case .hideItems:
                    button.image = ControlItemImages.circleFilled
                case .showItems:
                    button.image = ControlItemImages.circleStroked
                }
            }
        }

        guard let section else {
            return
        }

        updateLength(section: section)
        updateButton(section: section)

        statusBar?.needsSave = true
    }

    @objc private func performAction() {
        guard
            let statusBar,
            let event = NSApp.currentEvent
        else {
            return
        }
        switch event.type {
        case .leftMouseDown where NSEvent.modifierFlags == .option:
            statusBar.section(withName: .alwaysHidden)?.show()
        case .leftMouseDown:
            section?.toggle()
        case .rightMouseUp:
            statusItem.showMenu(createMenu(with: statusBar))
        default:
            break
        }
    }

    /// Creates and returns a menu to show when the control item is
    /// right-clicked.
    private func createMenu(with statusBar: StatusBar) -> NSMenu {
        let menu = NSMenu(title: Constants.appName)

        // add menu items to toggle the hidden and always-hidden sections,
        // assuming each section is enabled
        let sectionNames: [StatusBarSection.Name] = [.hidden, .alwaysHidden]
        for name in sectionNames {
            guard
                let section = statusBar.section(withName: name),
                section.isEnabled
            else {
                continue
            }
            let item = NSMenuItem(
                title: "\(section.isHidden ? "Show" : "Hide") \"\(name.rawValue)\" Section",
                action: #selector(toggleStatusBarSection),
                keyEquivalent: ""
            )
            item.target = self
            Self.storage[item] = section
            if let hotkey = section.hotkey {
                item.keyEquivalent = hotkey.key.keyEquivalent
                item.keyEquivalentModifierMask = hotkey.modifiers.nsEventFlags
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(Constants.appName)",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    /// Action for a menu item in the control item's menu to perform.
    @objc private func toggleStatusBarSection(for menuItem: NSMenuItem) {
        Self.storage[menuItem]?.toggle()
    }

    deinit {
        // removing the status item has the unwanted side effect of deleting
        // the preferred position; cache and restore after removing
        let autosaveName = autosaveName
        let cached = PreferredPosition[autosaveName]
        defer {
            PreferredPosition[autosaveName] = cached
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

// MARK: ControlItem: Codable
extension ControlItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case autosaveName
        case state
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            autosaveName: container.decode(String.self, forKey: .autosaveName),
            position: nil,
            state: container.decode(HidingState.self, forKey: .state)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autosaveName, forKey: .autosaveName)
        try container.encode(state, forKey: .state)
    }
}

// MARK: ControlItem: Equatable
extension ControlItem: Equatable {
    static func == (lhs: ControlItem, rhs: ControlItem) -> Bool {
        lhs.statusItem == rhs.statusItem &&
        lhs.autosaveName == rhs.autosaveName &&
        lhs.position == rhs.position &&
        lhs.state == rhs.state
    }
}

// MARK: ControlItem: Hashable
extension ControlItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(statusItem)
        hasher.combine(autosaveName)
        hasher.combine(position)
        hasher.combine(state)
    }
}

// MARK: - PreferredPosition
/// A proxy getter and setter for a control item's preferred position.
private enum PreferredPosition {
    private static func key(for autosaveName: String) -> String {
        return "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// Accesses the preferred position associated with the specified autosave name.
    static subscript(autosaveName: String) -> CGFloat? {
        get {
            // use object(forKey:) because double(forKey:) returns 0 if no value
            // is stored; we need to differentiate between "a stored value of 0"
            // and "no stored value"
            UserDefaults.standard.object(forKey: key(for: autosaveName)) as? CGFloat
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key(for: autosaveName))
        }
    }
}

// MARK: - ControlItemImages

/// Namespace for control item images.
enum ControlItemImages {
    static let circleFilled: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { bounds in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: bounds).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static let circleStroked: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { bounds in
            let lineWidth: CGFloat = 1.5
            let path = NSBezierPath(ovalIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            path.lineWidth = lineWidth
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static let (largeChevron, smallChevron): (NSImage, NSImage) = {
        func chevron(size: NSSize, lineWidth: CGFloat = 2) -> NSImage {
            let image = NSImage(size: size, flipped: false) { bounds in
                let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let path = NSBezierPath()
                path.move(to: NSPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.maxY))
                path.line(to: NSPoint(x: (insetBounds.minX + insetBounds.midX) / 2, y: insetBounds.midY))
                path.line(to: NSPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.minY))
                path.lineWidth = lineWidth
                path.lineCapStyle = .butt
                NSColor.black.setStroke()
                path.stroke()
                return true
            }
            image.isTemplate = true
            return image
        }
        let largeChevron = chevron(size: NSSize(width: 12, height: 12))
        let smallChevron = chevron(size: NSSize(width: 9, height: 9))
        return (largeChevron, smallChevron)
    }()
}
