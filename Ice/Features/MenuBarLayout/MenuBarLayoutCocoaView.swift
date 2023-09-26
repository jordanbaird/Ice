//
//  MenuBarLayoutCocoaView.swift
//  Ice
//

import Cocoa

// MARK: - MenuBarLayoutCocoaView

/// A Cocoa view that manages the menu bar layout interface.
class MenuBarLayoutCocoaView: NSView {
    private let container: MenuBarLayoutContainer

    /// The amount of spacing between each arranged view.
    var spacing: CGFloat {
        get { container.spacing }
        set { container.spacing = newValue }
    }

    /// The layout view's arranged views.
    ///
    /// The views are laid out from left to right in the order that they
    /// appear in the array. The ``spacing`` property determines the amount
    /// of space between each view.
    var arrangedViews: [MenuBarLayoutItemView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout view with the given spacing and initial value
    /// for its arranged views.
    ///
    /// - Parameters:
    ///   - spacing: The amount of space between each arranged view.
    ///   - arrangedViews: The layout view's initial arranged views.
    init(spacing: CGFloat, arrangedViews: [MenuBarLayoutItemView]) {
        self.container = MenuBarLayoutContainer(
            spacing: spacing,
            arrangedViews: arrangedViews
        )

        super.init(frame: .zero)
        addSubview(self.container)

        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // constrain height to a constant 60
            self.heightAnchor.constraint(
                equalToConstant: 60
            ),

            // center the container along the y axis
            self.container.centerYAnchor.constraint(
                equalTo: self.centerYAnchor
            ),

            // give the container 20 points of trailing spacing
            self.trailingAnchor.constraint(
                equalTo: self.container.trailingAnchor,
                constant: 20
            ),

            // allow variable spacing between leading anchors to let the view stretch
            // to fit whatever size is required; container should remain aligned toward
            // the trailing edge; this view is itself nested in a scroll view, so if it
            // has to expand to a larger size, it can be clipped
            self.leadingAnchor.constraint(
                lessThanOrEqualTo: self.container.leadingAnchor,
                constant: -20
            ),
        ])

        registerForDraggedTypes([.layoutItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if 
            let sourceView = sender?.draggingSource as? MenuBarLayoutItemView,
            let sourceIndex = container.arrangedViews.firstIndex(of: sourceView)
        {
            container.arrangedViews.remove(at: sourceIndex)
            sourceView.oldContainerInfo = (container, sourceIndex)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingSource is MenuBarLayoutItemView &&
        sender.draggingSourceOperationMask == .move
    }
}

// MARK: - MenuBarLayoutContainer

/// A container for the items in the menu bar layout interface.
///
/// The purpose of a container view is to hold visual representations of
/// the status items in the menu bar. As an implementation detail, container
/// views also manage the layout of those representations on behalf of a
/// parent view.
///
/// As the container updates the layout of its arranged status item views,
/// it automatically resizes itself using constraints that it maintains
/// internally. The container view is displayed inside of a parent view (an
/// instance of ``MenuBarLayoutCocoaView``), and is never presented as a
/// standalone view. The parent view provides space for the container view
/// to "float" in as it grows and shrinks according to the number of arranged
/// views it holds. The width of the parent view is constrained to be greater
/// than or equal to that of the container. To mimic the appearance of the
/// system menu bar, the parent view pins the trailing edge of the container
/// view to its own trailing edge. This ensures that any aforementioned
/// "floating" occurs on the container's leading edge.
class MenuBarLayoutContainer: NSView {
    /// Cached width constraint for the container view.
    private lazy var widthConstraint: NSLayoutConstraint = {
        let constraint = widthAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    /// Cached height constraint for the container view.
    private lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    /// The amount of spacing between each arranged view.
    var spacing: CGFloat {
        didSet {
            layoutArrangedViews()
        }
    }

    /// The contaner's arranged views.
    ///
    /// The views are laid out from left to right in the order that they
    /// appear in the array. The ``spacing`` property determines the amount
    /// of space between each view.
    var arrangedViews: [MenuBarLayoutItemView] {
        didSet {
            layoutArrangedViews(oldViews: oldValue)
        }
    }

    /// Creates a container view with the given spacing and initial
    /// value for its arranged views.
    ///
    /// - Parameters:
    ///   - spacing: The amount of space between each arranged view.
    ///   - arrangedViews: The container view's initial arranged views.
    init(spacing: CGFloat, arrangedViews: [MenuBarLayoutItemView]) {
        self.spacing = spacing
        self.arrangedViews = arrangedViews
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Performs layout of the container's arranged views.
    ///
    /// The container removes from its subviews the views that are included
    /// in the `oldViews` array but not in the the current ``arrangedViews``
    /// array. Views that are found in both arrays, but at different indices
    /// are animated from their old index to their new index.
    ///
    /// - Parameter oldViews: The old value of the container's arranged views.
    ///   Pass `nil` to use the current ``arrangedViews`` array.
    private func layoutArrangedViews(oldViews: [MenuBarLayoutItemView]? = nil) {
        let oldViews = oldViews ?? arrangedViews

        // remove views that are no longer part of the arranged views
        for view in oldViews where !arrangedViews.contains(view) {
            view.removeFromSuperview()
        }

        // retain the previous view on each iteration; use its frame
        // to calculate the x coordinate of the next view's origin
        var previous: NSView?

        // get the max height of all arranged views to calculate the
        // y coordinate of each view's origin
        let maxHeight = arrangedViews.lazy
            .map { $0.bounds.height }
            .max() ?? 0

        for var view in arrangedViews {
            if subviews.contains(view) {
                // view already exists inside the layout view, but may
                // have moved from its previous location; replace with
                // its animator proxy to animate the change
                view = view.animator()
            } else {
                // view does not already exist inside the layout view;
                // add it as a subview
                addSubview(view)
            }

            // set the view's origin; if the view is an animator proxy,
            // it will animate to the new position; otherwise, it must
            // be a newly added view
            view.setFrameOrigin(
                CGPoint(
                    x: previous.map { $0.frame.maxX + spacing } ?? 0,
                    y: (maxHeight / 2) - view.bounds.midY
                )
            )

            previous = view // retain the view
        }

        // update the width and height constraints using the information
        // collected while iterating
        widthConstraint.constant = previous?.frame.maxX ?? 0
        heightConstraint.constant = maxHeight
    }

    /// Updates the positions of the container's arranged views using
    /// the specified dragging information and returns an appropriate
    /// drag operation.
    func updateArrangedViewsForDrag(with draggingInfo: NSDraggingInfo) -> NSDragOperation {
        guard let sourceView = draggingInfo.draggingSource as? MenuBarLayoutItemView else {
            return []
        }
        // since the standard path relies on the presence of other arranged
        // views, handle the special case of an empty container here
        guard !arrangedViews.isEmpty else {
            arrangedViews.append(sourceView)
            return .move
        }
        draggingInfo.enumerateDraggingItems(
            for: self,
            classes: [NSPasteboardItem.self]
        ) { [weak self] draggingItem, _, stop in
            stop.pointee = true // only need the first item
            guard
                let self,
                let destinationView = arrangedView(nearestTo: draggingItem.draggingFrame.midX),
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return
            }
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                // source view is already inside this container, so move
                // it from its old index to the new one
                var targetIndex = destinationIndex
                if destinationIndex > sourceIndex {
                    targetIndex += 1
                }
                arrangedViews.move(fromOffsets: [sourceIndex], toOffset: targetIndex)
            } else {
                // source view is being dragged into this container from
                // another container, so just insert it
                arrangedViews.insert(sourceView, at: destinationIndex)
                sourceView.oldContainerInfo = nil
            }
        }
        return .move
    }

    /// Returns the nearest arranged view to the given X position within
    /// the coordinate system of the container view.
    ///
    /// The nearest arranged view is defined as the arranged view whose
    /// horizontal center is closest to `xPosition`.
    ///
    /// - Parameter xPosition: A floating point value representing an X
    ///   position within the coordinate system of the container view.
    func arrangedView(nearestTo xPosition: CGFloat) -> MenuBarLayoutItemView? {
        arrangedViews.min { view1, view2 in
            let distance1 = abs(view1.frame.midX - xPosition)
            let distance2 = abs(view2.frame.midX - xPosition)
            return distance1 < distance2
        }
    }
}
