//
//  LayoutBarItemView.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
class LayoutBarItemView: NSView {
    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The menu bar item info that the view represents.
    let info: MenuBarItemInfo

    /// The image displayed inside the view.
    var image: NSImage?

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainerView, index: Int)?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// A Boolean value that indicates whether the item view is a dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view's item is unresponsive.
    var isUnresponsive: Bool { false }

    /// Creates a view that displays the given menu bar item info.
    init(frame: CGRect, appState: AppState, info: MenuBarItemInfo) {
        self.appState = appState
        self.info = info
        super.init(frame: frame)
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Menu bar item is not movable."
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        return provideAlertForDisabledItem()
    }

    /// Provides an alert to display when the user is pressing a key while
    /// moving a menu bar item.
    func provideAlertForKeyDown() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Cannot move menu bar items while keys are pressed."
        return alert
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            image?.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.67
            )
            if isUnresponsive {
                let warningImage = NSImage.warning
                let width: CGFloat = 15
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard event.modifierFlags.isEmpty else {
            let alert = provideAlertForKeyDown()
            alert.runModal()
            return
        }

        guard isEnabled else {
            let alert = provideAlertForDisabledItem()
            alert.runModal()
            return
        }

        guard !isUnresponsive else {
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        // Contents of the pasteboard item don't matter here, as all needed information
        // is available directly from the dragging session. What matters is that the type
        // is set to `layoutBarItem`, as that is what the layout bar registers for.
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // Make sure the container doesn't update its arranged views and that items
        // aren't arranged during a dragging session.
        if let container = superview as? LayoutBarContainerView {
            container.canSetArrangedViews = false
        }

        // Prevent the dragging image from animating back to its original location.
        session.animatesToStartingPositionsOnCancelOrFail = false

        // Async to prevent the view from disappearing before the dragging image appears.
        DispatchQueue.main.async {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer {
            // Always remove container info at the end of a session.
            oldContainerInfo = nil
        }

        // Since the session's `animatesToStartingPositionsOnCancelOrFail` property was
        // set to false when the session began (above), there is no delay between the user
        // releasing the dragging item and this method being called. Thus, `isDraggingPlaceholder`
        // only needs to be updated here. If we ever decide we want animation, it may also
        // need to be updated inside `performDragOperation(_:)` on `LayoutBarPaddingView`.
        isDraggingPlaceholder = false

        // If the drop occurs outside of a container, reinsert the view into its original
        // container at its original index.
        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem { }

// MARK: - StandardLayoutBarItemView

final class StandardLayoutBarItemView: LayoutBarItemView {
    /// The item that this view represents.
    let item: MenuBarItem

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    override var isUnresponsive: Bool {
        Bridging.responsivity(for: item.ownerPID) == .unresponsive
    }

    override var image: NSImage? {
        didSet {
            if
                let image,
                let screen = appState?.imageCache.screen
            {
                let size = CGSize(
                    width: image.size.width / screen.backingScaleFactor,
                    height: image.size.height / screen.backingScaleFactor
                )
                setFrameSize(size)
            } else {
                setFrameSize(.zero)
            }
            needsDisplay = true
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        super.init(
            frame: CGRect(origin: .zero, size: item.frame.size),
            appState: appState,
            info: item.info
        )
        self.toolTip = item.displayName
        self.isEnabled = item.isMovable
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.imageCache.$images
                .sink { [weak self] images in
                    guard
                        let self,
                        let cgImage = images[item.info]
                    else {
                        return
                    }
                    image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                }
                .store(in: &c)
        }

        cancellables = c
    }

    override func provideAlertForDisabledItem() -> NSAlert {
        let alert = super.provideAlertForDisabledItem()
        alert.informativeText = "macOS prohibits \"\(item.displayName)\" from being moved."
        return alert
    }

    override func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = super.provideAlertForUnresponsiveItem()
        alert.informativeText = "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved."
        return alert
    }
}

// MARK: - SpecialLayoutBarItemView

final class SpecialLayoutBarItemView: LayoutBarItemView {
    enum Kind: NSString {
        case newItems = "New items appear here →"

        var color: NSColor {
            switch self {
            case .newItems: NSColor.controlAccentColor.withAlphaComponent(0.75)
            }
        }

        var info: MenuBarItemInfo {
            switch self {
            case .newItems: .newItems
            }
        }
    }

    let kind: Kind

    init(kind: Kind, appState: AppState) {
        self.kind = kind

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = kind.rawValue.size(withAttributes: labelAttributes)

        super.init(
            frame: CGRect(x: 0, y: 0, width: labelSize.width + 10, height: 22),
            appState: appState,
            info: kind.info
        )

        self.image = NSImage(size: bounds.size, flipped: false) { rect in
            kind.color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let centeredRect = CGRect(
                x: rect.midX - labelSize.width / 2,
                y: rect.midY - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            kind.rawValue.draw(in: centeredRect, withAttributes: labelAttributes)
            return true
        }
    }
}

// MARK: Layout Bar Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
