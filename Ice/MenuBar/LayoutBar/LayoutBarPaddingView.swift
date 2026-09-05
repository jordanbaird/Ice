//
//  LayoutBarPaddingView.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A Cocoa view that manages the menu bar layout interface.
final class LayoutBarPaddingView: NSView {
    private let container: LayoutBarContainer
    private var localDropIndicatorX: CGFloat?

    /// Only inspect views in Ice's own Settings window; no global input monitor.
    static func localDropTarget(in view: NSView, at windowPoint: CGPoint) -> LayoutBarPaddingView? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let target = view as? LayoutBarPaddingView,
           target.visibleRect.contains(target.convert(windowPoint, from: nil)) {
            return target
        }
        for child in view.subviews {
            if let target = localDropTarget(in: child, at: windowPoint) { return target }
        }
        return nil
    }

    private func localInsertion(for item: MenuBarItem, at windowPoint: CGPoint) -> (views: [LayoutBarItemView], index: Int) {
        let views = arrangedViews.filter { $0.item.tag != item.tag }
        let x = container.convert(windowPoint, from: nil).x
        return (views, views.firstIndex { x < $0.frame.midX } ?? views.endIndex)
    }

    func showLocalDropIndicator(for item: MenuBarItem, at windowPoint: CGPoint) {
        let insertion = localInsertion(for: item, at: windowPoint)
        let x = insertion.views.indices.contains(insertion.index)
            ? insertion.views[insertion.index].frame.minX - LayoutBarContainer.itemSpacing / 2
            : (insertion.views.last?.frame.maxX ?? 0) + LayoutBarContainer.itemSpacing / 2
        localDropIndicatorX = convert(CGPoint(x: x, y: 0), from: container).x
        needsDisplay = true
    }

    func clearLocalDropIndicator() {
        localDropIndicatorX = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let x = localDropIndicatorX {
            NSColor.controlAccentColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: visibleRect.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: CGRect(x: x - 1.5, y: bounds.midY - 27, width: 3, height: 54), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    func acceptLocalDrop(item: MenuBarItem, at windowPoint: CGPoint) {
        guard let appState = container.appState else { return }
        let insertion = localInsertion(for: item, at: windowPoint)
        // Dropping an item back into its own position is a no-op, including
        // an otherwise empty row. Never start a native drag for this case.
        if let originalIndex = arrangedViews.firstIndex(where: { $0.item.tag == item.tag }),
           originalIndex == insertion.index {
            return
        }
        let destination: MenuBarItemManager.MoveDestination?
        if insertion.views.indices.contains(insertion.index) {
            destination = .leftOfItem(insertion.views[insertion.index].item)
        } else if let last = insertion.views.last {
            destination = .rightOfItem(last.item)
        } else {
            destination = nil
        }
        Task {
            do {
                if let destination {
                    try await appState.itemManager.move(
                        item: item, to: destination, requiredSection: container.section
                    )
                } else {
                    try await appState.itemManager.move(item: item, toSection: container.section)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// The layout view's arranged views.
    var arrangedViews: [LayoutBarItemView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout bar view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.container = LayoutBarContainer(appState: appState, section: section)

        super.init(frame: .zero)

        addSubview(container)
        self.translatesAutoresizingMaskIntoConstraints = false

        var constraints = [container.centerYAnchor.constraint(equalTo: centerYAnchor)]
        if #available(macOS 27.0, *) {
            // Only real items occupy positions. The remaining row is a single
            // append target, not a right-aligned bank of empty slots.
            constraints += [
                container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor, constant: 12),
            ]
        } else {
            constraints += [
                trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 7.5),
                leadingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -7.5),
            ]
        }
        NSLayoutConstraint.activate(constraints)

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
        guard let draggingSource = sender.draggingSource as? LayoutBarItemView else {
            container.canSetArrangedViews = true
            return false
        }
        defer {
            DispatchQueue.main.async {
                guard !draggingSource.isAwaitingPhysicalMove else { return }
                self.container.canSetArrangedViews = true
                draggingSource.oldContainerInfo?.container.canSetArrangedViews = true
            }
        }
        // `draggingSession(_:endedAt:operation:)` clears this immediately
        // after the drop. Retain it for an asynchronous physical-move failure
        // so Layout can return the same view to its exact original slot.
        let rollbackOrigin = draggingSource.oldContainerInfo

        // A cache update racing the drag can create a replacement view for the
        // same menu-bar tag while the original drag source is still alive.
        // Normalize to the real source object before choosing a neighbor; a
        // duplicate otherwise lets the move resolve to "Wi-Fi left of Wi-Fi".
        let sourceTag = draggingSource.item.tag
        let sourceIsArranged = arrangedViews.contains { $0 === draggingSource }
        var didInsertSource = false
        let normalizedViews = arrangedViews.compactMap { view -> LayoutBarItemView? in
            guard view.item.tag == sourceTag else { return view }
            if sourceIsArranged {
                guard view === draggingSource, !didInsertSource else { return nil }
            } else {
                guard !didInsertSource else { return nil }
            }
            didInsertSource = true
            return draggingSource
        }
        let hasSameIdentityOrder = normalizedViews.count == arrangedViews.count &&
            zip(normalizedViews, arrangedViews).allSatisfy { pair in
                pair.0 === pair.1
            }
        if !hasSameIdentityOrder {
            arrangedViews = normalizedViews
        }

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                if #available(macOS 27.0, *) {
                    move(
                        view: draggingSource,
                        toSection: container.section,
                        rollbackOrigin: rollbackOrigin
                    )
                    return true
                }
                Task {
                    // dragging source is the only view in the layout bar, so we
                    // need to find a target item
                    let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                    let targetItem: MenuBarItem? = switch container.section {
                    case .visible: nil // visible section always has more than 1 item
                    case .hidden: items.first(matching: .hiddenControlItem)
                    case .alwaysHidden: items.first(matching: .alwaysHiddenControlItem)
                    }
                    if let targetItem {
                        move(
                            view: draggingSource,
                            to: .leftOfItem(targetItem),
                            rollbackOrigin: rollbackOrigin
                        )
                    } else {
                        Logger.default.error("No target item for layout bar drag")
                    }
                }
            } else if arrangedViews.indices.contains(index + 1) {
                // we have a view to the right of the dragging source
                let targetItem = arrangedViews[index + 1].item
                guard targetItem.tag != draggingSource.item.tag else { return false }
                move(
                    view: draggingSource,
                    to: .leftOfItem(targetItem),
                    rollbackOrigin: rollbackOrigin
                )
            } else if arrangedViews.indices.contains(index - 1) {
                // we have a view to the left of the dragging source
                let targetItem = arrangedViews[index - 1].item
                guard targetItem.tag != draggingSource.item.tag else { return false }
                move(
                    view: draggingSource,
                    to: .rightOfItem(targetItem),
                    rollbackOrigin: rollbackOrigin
                )
            }
        }

        return true
    }

    private func move(
        view: LayoutBarItemView,
        to destination: MenuBarItemManager.MoveDestination,
        rollbackOrigin: (container: LayoutBarContainer, index: Int)?
    ) {
        guard let appState = container.appState else {
            return
        }
        view.didAcceptCurrentDrop = true
        view.isAwaitingPhysicalMove = true
        Task {
            do {
                // Let AppKit finish the drop callback without imposing a
                // fixed delay before the physical menu-bar move begins.
                await Task.yield()
                if
                    let rollbackOrigin,
                    rollbackOrigin.container !== container
                {
                    // The drop already knows its destination section. Preserve
                    // that intent when selecting the physical target.
                    try await appState.itemManager.move(
                        item: view.item,
                        to: destination,
                        requiredSection: container.section
                    )
                } else {
                    try await appState.itemManager.move(item: view.item, to: destination)
                }
                appState.itemManager.removeTemporarilyShownItemFromCache(with: view.item.tag)
                completeSuccessfulDrop(
                    view: view,
                    from: rollbackOrigin,
                    appState: appState
                )
            } catch is CancellationError {
                view.isAwaitingPhysicalMove = false
                rollback(view: view, to: rollbackOrigin, appState: appState)
                return
            } catch {
                view.isAwaitingPhysicalMove = false
                Logger.default.error("Error moving menu bar item: \(error, privacy: .public)")
                rollback(view: view, to: rollbackOrigin, appState: appState)
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func move(
        view: LayoutBarItemView,
        toSection section: MenuBarSection.Name,
        rollbackOrigin: (container: LayoutBarContainer, index: Int)?
    ) {
        guard let appState = container.appState else { return }
        view.didAcceptCurrentDrop = true
        view.isAwaitingPhysicalMove = true
        Task {
            do {
                // Let AppKit finish the drop callback without imposing a
                // fixed delay before the physical menu-bar move begins.
                await Task.yield()
                try await appState.itemManager.move(item: view.item, toSection: section)
                appState.itemManager.removeTemporarilyShownItemFromCache(with: view.item.tag)
                completeSuccessfulDrop(
                    view: view,
                    from: rollbackOrigin,
                    appState: appState
                )
            } catch is CancellationError {
                view.isAwaitingPhysicalMove = false
                rollback(view: view, to: rollbackOrigin, appState: appState)
                return
            } catch {
                view.isAwaitingPhysicalMove = false
                Logger.default.error("Error moving menu bar item: \(error, privacy: .public)")
                rollback(view: view, to: rollbackOrigin, appState: appState)
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Releases the drag-time container freeze only after the physical move
    /// has been verified and projected into itemCache, then synchronizes both
    /// sections once. Stale AX snapshots arriving during the move are ignored.
    private func completeSuccessfulDrop(
        view: LayoutBarItemView,
        from origin: (container: LayoutBarContainer, index: Int)?,
        appState: AppState
    ) {
        view.isAwaitingPhysicalMove = false
        container.canSetArrangedViews = true
        origin?.container.canSetArrangedViews = true

        if let sourceContainer = origin?.container, sourceContainer !== container {
            sourceContainer.setArrangedViews(
                items: appState.itemManager.itemCache.managedItems(for: sourceContainer.section)
            )
        }
        container.setArrangedViews(
            items: appState.itemManager.itemCache.managedItems(for: container.section)
        )
    }

    /// Restores the exact pre-drag view ordering after a physical move fails.
    /// Reusing the same view avoids the duplicate image subscription and blink
    /// caused by tearing down and recreating a Layout tile during rollback.
    private func rollback(
        view: LayoutBarItemView,
        to origin: (container: LayoutBarContainer, index: Int)?,
        appState: AppState
    ) {
        container.canSetArrangedViews = true
        guard let origin else {
            container.setArrangedViews(
                items: appState.itemManager.itemCache.managedItems(for: container.section)
            )
            return
        }

        origin.container.canSetArrangedViews = true
        if origin.container === container {
            var views = container.arrangedViews
            views.removeAll { $0 === view }
            views.insert(view, at: min(origin.index, views.endIndex))
            container.arrangedViews = views
            return
        }

        var destinationViews = container.arrangedViews
        destinationViews.removeAll { $0 === view }
        container.arrangedViews = destinationViews

        var sourceViews = origin.container.arrangedViews
        sourceViews.removeAll { $0 === view }
        sourceViews.insert(view, at: min(origin.index, sourceViews.endIndex))
        origin.container.arrangedViews = sourceViews
    }
}
