//
//  LayoutBarScrollView.swift
//  Ice
//

import Cocoa
import Combine

final class LayoutBarScrollableCocoaView: NSScrollView {
    private let baseView: LayoutBarCocoaView

    /// The amount of space between each arranged view.
    var spacing: CGFloat {
        get { baseView.spacing }
        set { baseView.spacing = newValue }
    }

    /// The layout view's arranged views.
    ///
    /// The views are laid out from left to right in the order that they appear in
    /// the array. The ``spacing`` property determines the amount of space between
    /// each view.
    var arrangedViews: [LayoutBarItemView] {
        get { baseView.arrangedViews }
        set { baseView.arrangedViews = newValue }
    }

    /// Creates a layout bar scroll view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    ///   - spacing: The amount of space between each arranged view.
    init(appState: AppState, section: MenuBarSection, spacing: CGFloat) {
        self.baseView = LayoutBarCocoaView(appState: appState, section: section, spacing: spacing)

        super.init(frame: .zero)

        self.hasHorizontalScroller = true
        self.horizontalScroller = HorizontalScroller()

        self.autohidesScrollers = true

        self.verticalScrollElasticity = .none
        self.horizontalScrollElasticity = .none

        self.drawsBackground = false

        self.documentView = self.baseView

        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Constrain the base view's height to the content view's height.
            baseView.heightAnchor.constraint(equalTo: contentView.heightAnchor),

            // Constrain the base view's width to greater than or equal to the content
            // view's width.
            baseView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),

            // Constrain the base view's trailing anchor to the content view's trailing
            // anchor. This, in combination with the above width constraint, aligns the
            // items in the layout bar to the trailing edge.
            baseView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LayoutBarScrollableCocoaView {
    override func accessibilityChildren() -> [Any]? {
        return arrangedViews
    }
}

extension LayoutBarScrollableCocoaView {
    /// A custom scroller for a layout bar.
    final class HorizontalScroller: NSScroller {
        override static var isCompatibleWithOverlayScrollers: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.controlSize = .mini
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

// MARK: - LayoutBarCocoaView

/// A Cocoa view that manages the menu bar layout interface.
final class LayoutBarCocoaView: NSView {
    private let container: LayoutBarContainerView

    /// The section whose items are represented.
    var section: MenuBarSection {
        container.section
    }

    /// The amount of space between each arranged view.
    var spacing: CGFloat {
        get { container.spacing }
        set { container.spacing = newValue }
    }

    /// The layout view's arranged views.
    ///
    /// The views are laid out from left to right in the order that they
    /// appear in the array. The ``spacing`` property determines the amount
    /// of space between each view.
    var arrangedViews: [LayoutBarItemView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout bar view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    ///   - spacing: The amount of space between each arranged view.
    init(appState: AppState, section: MenuBarSection, spacing: CGFloat) {
        self.container = LayoutBarContainerView(appState: appState, section: section, spacing: spacing)

        super.init(frame: .zero)
        addSubview(self.container)

        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Center the container along the y axis.
            container.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Give the container a few points of trailing space.
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 7.5),

            // Allow variable spacing between leading anchors to let the view stretch
            // to fit whatever size is required. The container should remain aligned
            // toward the trailing edge. This view is itself nested in a scroll view,
            // so if it has to expand to a larger size, it can be clipped.
            leadingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -7.5),
        ])

        registerForDraggedTypes([.layoutBarItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender, phase: .entered)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender {
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            DispatchQueue.main.async {
                self.container.canSetArrangedViews = true
            }
        }

        guard
            sender.draggingSourceOperationMask == .move,
            let draggingSource = sender.draggingSource as? StandardLayoutBarItemView
        else {
            return false
        }

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                // The dragging source is the only view in the layout bar, so we need to find a target item.
                let items = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
                let targetItem: MenuBarItem? = switch section.name {
                case .visible: nil // Visible section always has more than 1 item.
                case .hidden: items.first { $0.info == .hiddenControlItem }
                case .alwaysHidden: items.first { $0.info == .alwaysHiddenControlItem }
                }
                if let targetItem {
                    move(item: draggingSource.item, to: .leftOfItem(targetItem))
                } else {
                    Logger.layoutBar.error("No target item for layout bar drag")
                }
            } else if arrangedViews.indices.contains(index + 1) {
                // We have a view to the right of the dragging source.
                if let targetItem = (arrangedViews[index + 1] as? StandardLayoutBarItemView)?.item {
                    move(item: draggingSource.item, to: .leftOfItem(targetItem))
                }
            } else if arrangedViews.indices.contains(index - 1) {
                // We have a view to the left of the dragging source.
                if let targetItem = (arrangedViews[index - 1] as? StandardLayoutBarItemView)?.item {
                    move(item: draggingSource.item, to: .rightOfItem(targetItem))
                }
            }
        }

        return true
    }

    private func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination) {
        guard let appState = container.appState else {
            return
        }
        Task {
            try await Task.sleep(for: .milliseconds(25))
            do {
                try await appState.itemManager.slowMove(item: item, to: destination)
                appState.itemManager.removeTempShownItemFromCache(with: item.info)
            } catch {
                Logger.layoutBar.error("Error moving menu bar item: \(error)")
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

// MARK: - LayoutBarContainerView

/// A container for the items in the menu bar layout interface.
final class LayoutBarContainerView: NSView {
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

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The section whose items are represented.
    let section: MenuBarSection

    /// A Boolean value that indicates whether the container should animate its next layout pass.
    ///
    /// After each layout pass, this value is reset to `true`.
    var shouldAnimateNextLayoutPass = true

    /// A Boolean value that indicates whether the container can set its arranged views.
    var canSetArrangedViews = true

    /// The amount of space between each arranged view.
    var spacing: CGFloat {
        didSet {
            layoutArrangedViews()
        }
    }

    /// The contaner's arranged views.
    ///
    /// The views are laid out from left to right in the order that they appear in the array.
    /// The ``spacing`` property determines the amount of space between each view.
    var arrangedViews = [LayoutBarItemView]() {
        didSet {
            layoutArrangedViews(oldViews: oldValue)
        }
    }

    /// Creates a container view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    ///   - spacing: The amount of space between each arranged view.
    init(appState: AppState, section: MenuBarSection, spacing: CGFloat) {
        self.appState = appState
        self.section = section
        self.spacing = spacing
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the internal observers for the container.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.itemManager.$itemCache
                .removeDuplicates()
                .sink { [weak self] cache in
                    guard let self else {
                        return
                    }
                    setArrangedViews(items: cache.managedItems(for: section.name))
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
    /// The container removes from its subviews the views that are included in the `oldViews`
    /// array but not in the the current ``arrangedViews`` array. Views that are found in both
    /// arrays, but at different indices are animated from their old index to their new index.
    ///
    /// - Parameter oldViews: The old value of the container's arranged views. Pass `nil` to
    ///   use the current ``arrangedViews`` array.
    private func layoutArrangedViews(oldViews: [LayoutBarItemView]? = nil) {
        defer {
            shouldAnimateNextLayoutPass = true
        }

        let oldViews = oldViews ?? arrangedViews

        // Remove views that are no longer part of the arranged views.
        for view in oldViews where !arrangedViews.contains(view) {
            view.removeFromSuperview()
            view.hasContainer = false
        }

        // Retain the previous view on each iteration. Use its frame to calculate the
        // x coordinate of the next view's origin.
        var previous: NSView?

        // Get the max height of all arranged views to calculate the y coordinate of
        // each view's origin.
        let maxHeight = arrangedViews.lazy
            .map { $0.bounds.height }
            .max() ?? 0

        for var view in arrangedViews {
            if subviews.contains(view) {
                // View already exists inside the layout view, but may have moved from
                // its previous location.
                if shouldAnimateNextLayoutPass {
                    // Replace the view with its animator proxy.
                    view = view.animator()
                }
            } else {
                // View does not already exist inside the layout view. Add it as a subview.
                addSubview(view)
                view.hasContainer = true
            }

            // Set the view's origin. If the view is an animator proxy, it will animate
            // to the new position. Otherwise, it must be a newly added view.
            view.setFrameOrigin(
                CGPoint(
                    x: previous.map { $0.frame.maxX + spacing } ?? 0,
                    y: (maxHeight / 2) - view.bounds.midY
                )
            )

            previous = view // Retain the view.
        }

        // Update the width and height constraints using the information collected
        // while iterating.
        widthConstraint.constant = previous?.frame.maxX ?? 0
        heightConstraint.constant = maxHeight
    }

    /// Sets the container's arranged views with the given items.
    ///
    /// - Note: If the value of the container's ``canSetArrangedViews`` property is `false`,
    ///   this function returns early.
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
            if let existingView = arrangedViews.first(where: { $0.info == item.info }) {
                newViews.append(existingView)
            } else {
                let view = StandardLayoutBarItemView(appState: appState, item: item)
                newViews.append(view)
            }
        }
        arrangedViews = newViews
    }

    /// Updates the positions of the container's arranged views using the specified
    /// dragging information and phase.
    ///
    /// - Parameters:
    ///   - draggingInfo: The dragging information to use to update the container's
    ///     arranged views.
    ///   - phase: The current dragging phase of the container.
    ///
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
            // Updating normally relies on the presence of other arranged views, but if the
            // container is empty, it needs to be handled separately.
            guard !arrangedViews.filter({ $0.isEnabled }).isEmpty else {
                arrangedViews.insert(sourceView, at: 0)
                return .move
            }
            // Convert dragging location from window coordinates.
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            guard
                let destinationView = arrangedView(nearestTo: draggingLocation.x),
                destinationView !== sourceView,
                // Don't rearrange if destination is disabled.
                destinationView.isEnabled,
                // Don't rearrange if in the middle of an animation.
                destinationView.layer?.animationKeys() == nil,
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return .move
            }
            // Drag must be near the horizontal center of the destination view to trigger a swap.
            let midX = destinationView.frame.midX
            let offset = destinationView.frame.width / 2
            if !((midX - offset)...(midX + offset)).contains(draggingLocation.x) {
                if sourceView.oldContainerInfo?.container === self {
                    return .move
                }
            }
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                // Source view is already inside this container, so move it from its old index
                // to the new one.
                var targetIndex = destinationIndex
                if destinationIndex > sourceIndex {
                    targetIndex += 1
                }
                arrangedViews.move(fromOffsets: [sourceIndex], toOffset: targetIndex)
            } else {
                // Source view is being dragged from another container, so just insert it.
                arrangedViews.insert(sourceView, at: destinationIndex)
            }
            return .move
        case .ended:
            return .move
        }
    }

    /// Returns the nearest arranged view to the given X position within the coordinate
    /// system of the container view.
    ///
    /// The nearest arranged view is defined as the arranged view whose horizontal center
    /// is closest to `xPosition`.
    ///
    /// - Parameter xPosition: A floating point value representing an X position within
    ///   the coordinate system of the container view.
    func arrangedView(nearestTo xPosition: CGFloat) -> LayoutBarItemView? {
        arrangedViews.min { view1, view2 in
            let distance1 = abs(view1.frame.midX - xPosition)
            let distance2 = abs(view2.frame.midX - xPosition)
            return distance1 < distance2
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let layoutBar = Logger(category: "LayoutBar")
}
