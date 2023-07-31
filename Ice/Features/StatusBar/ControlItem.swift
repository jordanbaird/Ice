//
//  ControlItem.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - ControlItemLengths

/// Namespace of possible control item lengths.
enum ControlItemLengths {
    static let collapsed: CGFloat = 25
    static let expanded: CGFloat = 10_000
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
        let smallChevron = chevron(size: NSSize(width: 7, height: 7))
        return (largeChevron, smallChevron)
    }()
}

// MARK: - ControlItem

final class ControlItem: ObservableObject {
    private let statusItem: NSStatusItem

    @Published private(set) var position: CGFloat?

    let autosaveName: String

    var state: State {
        didSet {
            updateStatusItem()
        }
    }

    weak var statusBar: StatusBar? {
        didSet {
            updateStatusItem()
        }
    }

    init(autosaveName: String? = nil, position: CGFloat? = nil, state: State? = nil) {
        let autosaveName = autosaveName ?? UUID().uuidString
        let state = state ?? .visible
        self.statusItem = {
            // set the preferred position first or the status item won't
            // recognize when it's been set
            PreferredPosition[autosaveName] = position
            let statusItem = NSStatusBar.system.statusItem(withLength: 0)
            // set the autosave name to associate the status item with the
            // preferred position
            statusItem.autosaveName = autosaveName
            return statusItem
        }()
        self.autosaveName = autosaveName
        self.position = position
        self.state = state
        configureStatusItem()
    }

    func configureStatusItem() {
        defer {
            updateStatusItem()
        }

        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(performAction)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])

        guard let window = button.window else {
            return
        }
        window.publisher(for: \.frame)
            .combineLatest(window.publisher(for: \.screen))
            .compactMap { frame, screen in
                // window is placed offscreen at first; only publish frames
                // that are at least partially onscreen
                guard
                    let screenFrame = screen?.frame,
                    screenFrame.intersects(frame)
                else {
                    return nil
                }
                // calculate position relative to trailing edge of screen
                return screenFrame.maxX - frame.maxX
            }
            .removeDuplicates()
            .assign(to: &$position)
    }

    /// Update the control item's status item to match the current state.
    func updateStatusItem() {
        guard let statusBar else {
            return
        }
        defer {
            statusBar.needsSaveControlItems = true
        }

        let length = statusBar.controlItemLength(for: self)
        statusItem.length = length

        guard let button = statusItem.button else {
            return
        }
        if length == ControlItemLengths.expanded {
            button.isHighlighted = false
            button.cell?.isEnabled = false
        } else {
            button.cell?.isEnabled = true
        }
        button.image = statusBar.controlItemImage(for: self)
    }

    @objc private func performAction() {
        guard
            let statusBar,
            let event = NSApp.currentEvent
        else {
            return
        }
        switch event.type {
        case .leftMouseDown where event.modifierFlags == .option:
            statusBar.showAllControlItems()
        case .leftMouseDown:
            statusBar.toggleControlItem(self)
        case .rightMouseUp:
            statusItem.showMenu(statusBar.menu)
        default:
            break
        }
    }

    deinit {
        // removing the status item has the unwanted side effect of deleting
        // the preferred position; cache and restore after removing
        let cached = PreferredPosition[autosaveName]
        defer {
            PreferredPosition[autosaveName] = cached
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

// MARK: ControlItem: Codable
extension ControlItem: Codable {
    private struct AutosaveNameCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = Int(stringValue)
        }

        init(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private enum PropertiesCodingKeys: String, CodingKey {
        case position = "Position"
        case state = "State"
    }

    convenience init(from decoder: Decoder) throws {
        let topLevelContainer = try decoder.container(keyedBy: AutosaveNameCodingKey.self)
        var keys = topLevelContainer.allKeys
        guard
            let key = keys.popLast(),
            keys.isEmpty
        else {
            let keyCount = topLevelContainer.allKeys.count
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a single keyed value but found \(keyCount)."
                )
            )
        }
        let propertiesContainer = try topLevelContainer.nestedContainer(
            keyedBy: PropertiesCodingKeys.self,
            forKey: key
        )
        try self.init(
            autosaveName: key.stringValue,
            position: propertiesContainer.decode(CGFloat.self, forKey: .position),
            state: propertiesContainer.decode(State.self, forKey: .state)
        )
    }

    func encode(to encoder: Encoder) throws {
        var topLevelContainer = encoder.container(keyedBy: AutosaveNameCodingKey.self)
        var propertiesContainer = topLevelContainer.nestedContainer(
            keyedBy: PropertiesCodingKeys.self,
            forKey: AutosaveNameCodingKey(stringValue: autosaveName)
        )
        try propertiesContainer.encode(position, forKey: .position)
        try propertiesContainer.encode(state, forKey: .state)
    }
}

// MARK: ControlItem: Equatable
extension ControlItem: Equatable {
    static func == (lhs: ControlItem, rhs: ControlItem) -> Bool {
        lhs.statusItem == rhs.statusItem &&
        lhs.position == rhs.position &&
        lhs.autosaveName == rhs.autosaveName &&
        lhs.state == rhs.state
    }
}

// MARK: ControlItem: Hashable
extension ControlItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(statusItem)
        hasher.combine(position)
        hasher.combine(autosaveName)
        hasher.combine(state)
    }
}

// MARK: - State
extension ControlItem {
    enum State: RawRepresentable, Hashable, Codable {
        case visible
        case hidden(isExpanded: Bool)

        var rawValue: Int {
            switch self {
            case .visible:
                return 0
            case .hidden(isExpanded: false):
                return 1
            case .hidden(isExpanded: true):
                return 2
            }
        }

        init?(rawValue: Int) {
            switch rawValue {
            case 0:
                self = .visible
            case 1:
                self = .hidden(isExpanded: false)
            case 2:
                self = .hidden(isExpanded: true)
            default:
                return nil
            }
        }
    }
}

// MARK: - PreferredPosition
extension ControlItem {
    /// A proxy getter and setter for a control item's preferred position.
    enum PreferredPosition {
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
}
