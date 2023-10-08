//
//  LayoutBarContainer.swift
//  Ice
//

import Cocoa

/// A container for the items in the menu bar layout interface.
///
/// The purpose of a container view is to hold visual representations of
/// the menu bar items in the menu bar. As an implementation detail, container
/// views also manage the layout of those representations on behalf of a
/// parent view.
///
/// As the container updates the layout of its arranged menu bar item views,
/// it automatically resizes itself using constraints that it maintains
/// internally. The container view is displayed inside of a parent view (an
/// instance of ``LayoutBarCocoaView``), and is never presented as a
/// standalone view. The parent view provides space for the container view
/// to "float" in as it grows and shrinks according to the number of arranged
/// views it holds. The width of the parent view is constrained to be greater
/// than or equal to that of the container. To mimic the appearance of the
/// system menu bar, the parent view pins the trailing edge of the container
/// view to its own trailing edge. This ensures that any aforementioned
/// "floating" occurs on the container's leading edge.
class LayoutBarContainer: NSView {
    /// Phases for a dragging session.
    enum DraggingPhase {
        case entered
        case exited
        case updated
        case ended
    }

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

    /// A Boolean value that indicates whether the container should
    /// animate its next layout pass.
    ///
    /// After each layout pass, this value is reset to `true`.
    var shouldAnimateNextLayoutPass = true

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
    var arrangedViews: [LayoutBarItemView] {
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
    init(spacing: CGFloat, arrangedViews: [LayoutBarItemView]) {
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
    private func layoutArrangedViews(oldViews: [LayoutBarItemView]? = nil) {
        defer {
            shouldAnimateNextLayoutPass = true
        }

        let oldViews = oldViews ?? arrangedViews

        // remove views that are no longer part of the arranged views
        for view in oldViews where !arrangedViews.contains(view) {
            view.removeFromSuperview()
            view.hasContainer = false
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
                // have moved from its previous location;
                if shouldAnimateNextLayoutPass {
                    // replace the view with its animator proxy
                    view = view.animator()
                }
            } else {
                // view does not already exist inside the layout view;
                // add it as a subview
                addSubview(view)
                view.hasContainer = true
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
    @discardableResult
    func updateArrangedViewsForDrag(with draggingInfo: NSDraggingInfo, phase: DraggingPhase) -> NSDragOperation {
        func draggingPhaseEntered(sourceView: LayoutBarItemView) -> NSDragOperation {
            shouldAnimateNextLayoutPass = false
            return draggingPhaseUpdated(sourceView: sourceView)
        }

        func draggingPhaseExited(sourceView: LayoutBarItemView) -> NSDragOperation {
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                shouldAnimateNextLayoutPass = false
                arrangedViews.remove(at: sourceIndex)
            }
            return .move
        }

        func draggingPhaseUpdated(sourceView: LayoutBarItemView) -> NSDragOperation {
            if
                sourceView.oldContainerInfo == nil,
                let sourceIndex = arrangedViews.firstIndex(of: sourceView)
            {
                sourceView.oldContainerInfo = (self, sourceIndex)
            }
            // updating normally relies on the presence of other
            // arranged views, but if the container is empty, it
            // needs to be handled separately
            guard !arrangedViews.isEmpty else {
                arrangedViews.append(sourceView)
                return .move
            }
            // convert dragging location from window coordinates
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            guard
                let destinationView = arrangedView(nearestTo: draggingLocation.x),
                // don't rearrange if destination is disabled
                destinationView.isEnabled,
                // don't rearrange if in the middle of an animation
                destinationView.layer?.animationKeys() == nil,
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return .move
            }
            if destinationView.frame.contains(draggingLocation) {
                // if drag is inside the destination view, it must
                // be near the horizontal center to trigger a swap
                let midX = destinationView.frame.midX
                if !((midX - 5)...(midX + 5)).contains(draggingLocation.x) {
                    return .move
                }
            }
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                // source view is already inside this container, so
                // move it from its old index to the new one
                var targetIndex = destinationIndex
                if destinationIndex > sourceIndex {
                    targetIndex += 1
                }
                arrangedViews.move(fromOffsets: [sourceIndex], toOffset: targetIndex)
            } else {
                // source view is being dragged into the container
                // from another container, so just insert it
                arrangedViews.insert(sourceView, at: destinationIndex)
            }
            return .move
        }

        func draggingPhaseEnded(sourceView: LayoutBarItemView) -> NSDragOperation {
            return .move
        }

        guard let sourceView = draggingInfo.draggingSource as? LayoutBarItemView else {
            return []
        }

        return switch phase {
        case .entered:
            draggingPhaseEntered(sourceView: sourceView)
        case .exited:
            draggingPhaseExited(sourceView: sourceView)
        case .updated:
            draggingPhaseUpdated(sourceView: sourceView)
        case .ended:
            draggingPhaseEnded(sourceView: sourceView)
        }
    }

    /// Returns the nearest arranged view to the given X position within
    /// the coordinate system of the container view.
    ///
    /// The nearest arranged view is defined as the arranged view whose
    /// horizontal center is closest to `xPosition`.
    ///
    /// - Parameter xPosition: A floating point value representing an X
    ///   position within the coordinate system of the container view.
    func arrangedView(nearestTo xPosition: CGFloat) -> LayoutBarItemView? {
        arrangedViews.min { view1, view2 in
            let distance1 = abs(view1.frame.midX - xPosition)
            let distance2 = abs(view2.frame.midX - xPosition)
            return distance1 < distance2
        }
    }
}
