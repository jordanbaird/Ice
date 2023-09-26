//
//  MenuBarLayoutItem.swift
//  Ice
//

import Cocoa

// MARK: - MenuBarLayoutItem

/// A type that produces a view for display in a menu bar
/// layout view.
struct MenuBarLayoutItem: Hashable, Identifiable {
    /// The item's displayed image.
    let image: NSImage

    var id: Int {
        image.hashValue
    }

    /// Creates and returns a view for display in a menu
    /// bar layout view.
    func makeItemView() -> MenuBarLayoutItemView {
        MenuBarLayoutItemView(image: image)
    }
}

// MARK: - MenuBarLayoutItemView

/// A view that displays an image in a menu bar layout view.
class MenuBarLayoutItemView: NSView {
    /// Temporary information that the item view retains when it is
    /// moved outside of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this
    /// property is set to hold the layout view's container view, as
    /// well as the index of the item view in relation to the container's
    /// other items. Upon being inserted into a new layout view, these
    /// values are removed. If the item is dropped outside of a layout
    /// view, these values are used to reinsert the item view in its
    /// original layout view.
    var oldContainerInfo: (container: MenuBarLayoutContainer, index: Int)?

    /// The image displayed inside the view.
    let image: NSImage

    /// A Boolean value that indicates whether the item view is a
    /// dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// Creates an item view that displays the given image.
    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            image.draw(in: bounds)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        let pasteboardItem = NSPasteboardItem()
        // contents of the pasteboard item don't matter here, as all needed
        // information is available directly from the dragging session; what
        // matters is that the type is set to `layoutItem`, as that is what
        // the layout view registers for
        pasteboardItem.setData(Data(), forType: .layoutItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: MenuBarLayoutItemView: NSDraggingSource
extension MenuBarLayoutItemView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        // prevent the dragging image from animating back to its
        // original location
        session.animatesToStartingPositionsOnCancelOrFail = false
        // async to prevent the view from disappearing before the
        // dragging image appears
        DispatchQueue.main.async {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // since the session's `animatesToStartingPositionsOnCancelOrFail`
        // property was set to false when the session began (above), there
        // is no delay between the user releasing the dragging item and
        // this method being called; thus, `isDraggingPlaceholder` only
        // needs to be updated here; if we ever decide we want animation,
        // it may also need to be updated inside `performDragOperation(_:)`
        // on `MenuBarLayoutCocoaView`
        isDraggingPlaceholder = false
        // reinsert the view if dropped outside of a layout view
        if let (container, index) = oldContainerInfo {
            container.arrangedViews.insert(self, at: index)
            oldContainerInfo = nil
        }
    }
}

// MARK: Layout Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutItem = Self("\(Bundle.main.bundleIdentifier!).layout-item")
}
