//
//  LayoutBarItem.swift
//  Ice
//

import Cocoa

// MARK: - LayoutBarItem

/// A type that produces a view for display in a menu bar
/// layout view.
struct LayoutBarItem: Hashable, Identifiable {
    let view: LayoutBarItemView

    var id: Int {
        view.image.hashValue
    }

    init(image: NSImage, toolTip: String, isEnabled: Bool) {
        self.view = LayoutBarItemView(
            image: image,
            toolTip: toolTip,
            isEnabled: isEnabled
        )
    }

    init(image: CGImage, size: CGSize, toolTip: String, isEnabled: Bool) {
        self.init(
            image: NSImage(cgImage: image, size: size), 
            toolTip: toolTip,
            isEnabled: isEnabled
        )
    }
}

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
class LayoutBarItemView: NSControl {
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
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// A Boolean value that indicates whether the item view is
    /// currently inside a container.
    var hasContainer = false

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
    init(image: NSImage, toolTip: String, isEnabled: Bool) {
        // only trim horizontal edges to maintain proper vertical
        // centering due to status item shadow offsetting the trim
        let trimmedImage = image.trimmingTransparentPixels(edges: [.minXEdge, .maxXEdge])
        self.image = trimmedImage ?? image
        // set the frame to the full image size; the trimmed image
        // will be centered within the full bounds when displayed
        super.init(frame: NSRect(origin: .zero, size: image.size))
        self.toolTip = toolTip
        self.isEnabled = isEnabled
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createImageForDisplay(from image: NSImage) -> NSImage {
        NSImage(size: bounds.size, flipped: false) { bounds in
            let rect = CGRect(
                x: bounds.midX - (image.size.width / 2),
                y: bounds.midY - (image.size.height / 2),
                width: image.size.width,
                height: image.size.height
            )
            image.draw(in: rect)
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            let displayImage = createImageForDisplay(from: image)
            displayImage.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : (2 / 3)
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard isEnabled else {
            return
        }

        let pasteboardItem = NSPasteboardItem()
        // contents of the pasteboard item don't matter here, as all needed
        // information is available directly from the dragging session; what
        // matters is that the type is set to `layoutBarItem`, as that is
        // what the layout bar registers for
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: createImageForDisplay(from: image))

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
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
        defer {
            // always remove container info at the end of a session
            oldContainerInfo = nil
        }
        // since the session's `animatesToStartingPositionsOnCancelOrFail`
        // property was set to false when the session began (above), there
        // is no delay between the user releasing the dragging item and
        // this method being called; thus, `isDraggingPlaceholder` only
        // needs to be updated here; if we ever decide we want animation,
        // it may also need to be updated inside `performDragOperation(_:)`
        // on `MenuBarLayoutCocoaView`
        isDraggingPlaceholder = false
        // if the drop occurs outside of a container, reinsert the view
        // into its original container at its original index
        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

// MARK: Layout Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Bundle.main.bundleIdentifier!).layout-bar-item")
}
