//
//  LayoutBarContainer.swift
//  Ice
//

import Cocoa
import Combine

/// A container for the items in the menu bar layout interface.
final class LayoutBarContainer: NSView {
    /// Phases for a dragging session.
    enum DraggingPhase {
        case entered, exited, updated, ended
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

    /// The shared app state instance.
    private(set) weak var appState: AppState?

    /// The section whose items are represented.
    let section: MenuBarSection.Name

    /// A Boolean value that indicates whether the container should
    /// animate its next layout pass.
    ///
    /// After each layout pass, this value is reset to `true`.
    var shouldAnimateNextLayoutPass = true

    /// A Boolean value that indicates whether the container can
    /// set its arranged views.
    var canSetArrangedViews = true

    /// The contaner's arranged views.
    ///
    /// The views are laid out from left to right in the order that they
    /// appear in the array. The ``spacing`` property determines the amount
    /// of space between each view.
    var arrangedViews = [LayoutBarItemView]() {
        didSet {
            layoutArrangedViews(oldViews: oldValue)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Creates a container view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.appState = appState
        self.section = section
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.itemManager.$itemCache
                .removeDuplicates()
                .sink { [weak self] cache in
                    guard let self else {
                        return
                    }
                    setArrangedViews(items: cache.managedItems(for: section))
                }
                .store(in: &c)

            appState.imageCache.$images
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    layoutArrangedViews()
                }
                .store(in: &c)
        }

        cancellables = c
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
                    x: previous.map { $0.frame.maxX } ?? 0,
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

    /// Sets the container's arranged views with the given items.
    ///
    /// - Note: If the value of the container's ``canSetArrangedViews``
    ///   property is `false`, this function returns early.
    func setArrangedViews(items: [MenuBarItem]?) {
        guard
            let appState,
            canSetArrangedViews
        else {
            return
        }
        guard let items else {
            arrangedViews.removeAll()
            return
        }
        var newViews = [LayoutBarItemView]()
        for item in items {
            if let existingView = arrangedViews.first(where: { $0.item == item }) {
                newViews.append(existingView)
            } else {
                let view = LayoutBarItemView(appState: appState, item: item)
                newViews.append(view)
            }
        }
        arrangedViews = newViews
    }

    /// Updates the positions of the container's arranged views using the
    /// specified dragging information and phase.
    ///
    /// - Parameters:
    ///   - draggingInfo: The dragging information to use to update the
    ///     container's arranged views.
    ///   - phase: The current dragging phase of the container.
    /// - Returns: A dragging operation.
    @discardableResult
    func updateArrangedViewsForDrag(with draggingInfo: NSDraggingInfo, phase: DraggingPhase) -> NSDragOperation {
        guard let sourceView = draggingInfo.draggingSource as? LayoutBarItemView else {
            return []
        }
        switch phase {
        case .entered:
            if !arrangedViews.contains(sourceView) {
                shouldAnimateNextLayoutPass = false
            }
            return updateArrangedViewsForDrag(with: draggingInfo, phase: .updated)
        case .exited:
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                shouldAnimateNextLayoutPass = false
                arrangedViews.remove(at: sourceIndex)
            }
            return .move
        case .updated:
            if
                sourceView.oldContainerInfo == nil,
                let sourceIndex = arrangedViews.firstIndex(of: sourceView)
            {
                sourceView.oldContainerInfo = (self, sourceIndex)
            }
            // updating normally relies on the presence of other arranged views,
            // but if the container is empty, it needs to be handled separately
            guard !arrangedViews.filter({ $0.isEnabled }).isEmpty else {
                arrangedViews.insert(sourceView, at: 0)
                return .move
            }
            // convert dragging location from window coordinates
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            guard
                let destinationView = arrangedView(nearestTo: draggingLocation.x),
                destinationView !== sourceView,
                // don't rearrange if destination is disabled
                destinationView.isEnabled,
                // don't rearrange if in the middle of an animation
                destinationView.layer?.animationKeys() == nil,
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return .move
            }
            // drag must be near the horizontal center of the destination
            // view to trigger a swap
            let midX = destinationView.frame.midX
            let offset = destinationView.frame.width / 2
            if !((midX - offset)...(midX + offset)).contains(draggingLocation.x) {
                if sourceView.oldContainerInfo?.container === self {
                    return .move
                }
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
                // source view is being dragged from another container,
                // so just insert it
                arrangedViews.insert(sourceView, at: destinationIndex)
            }
            return .move
        case .ended:
            return .move
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
