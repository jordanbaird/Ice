//
//  LayoutBarItemView.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: NSView {
    /// Each real item has one compact, labelled thumbnail. There are no
    /// placeholder views for empty positions or failed image captures.
    private static let minimumItemWidth: CGFloat = if #available(macOS 27.0, *) { 88 } else { 32 }
    private static let horizontalImageInset: CGFloat = 2

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()
    private var pendingMoveTask: Task<Void, Never>?
    private var pendingMoveOffset = 0
    private var pendingMoveIsExecuting = false
    private var localDropTarget: LayoutBarPaddingView?
    private var isLocalDragActive = false
    private var isHovered = false
    private var displayedImageIsTemplate = false

    /// The item that the view represents.
    private(set) var item: MenuBarItem

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// Keeps source and destination containers frozen between the visual drop
    /// and completion of the asynchronous physical menu-bar move.
    var isAwaitingPhysicalMove = false

    /// Distinguishes a destination that synchronously accepted this AppKit
    /// drag from a cancelled session whose final `draggingExited` can arrive
    /// after the source's ended callback.
    var didAcceptCurrentDrop = false
    var isDragSessionActive = false
    private var dragSessionGeneration = 0

    /// A Layout-only image with the capture's transparent side margins
    /// removed. The shared cache retains the original pixels for other views.
    private var displayedImage: NSImage?
    private var displayedImageSize = CGSize.zero

    /// The image displayed inside the view.
    private var cachedImage: MenuBarItemImageCache.CapturedImage? {
        didSet {
            guard cachedImage != oldValue else { return }
            if let image = cachedImage {
                let glyph: CGImage
                if #available(macOS 27.0, *) {
                    guard let result = MenuBarGlyphImage.make(from: image.cgImage) else { return }
                    glyph = result.image
                    displayedImageIsTemplate = result.isTemplate
                } else {
                    glyph = image.cgImage
                }
                let trimmed = glyph.trimmingTransparency(
                    around: [.minXEdge, .maxXEdge],
                    alphaThreshold: 0.05
                ) ?? glyph
                displayedImageSize = CGSize(
                    width: CGFloat(trimmed.width) / image.scale,
                    height: CGFloat(trimmed.height) / image.scale
                )
                displayedImage = NSImage(cgImage: trimmed, size: displayedImageSize)
                setFrameSize(
                    CGSize(
                        width: max(
                            Self.minimumItemWidth,
                            displayedImageSize.width + (Self.horizontalImageInset * 2) + thumbnailExtraWidth
                        ),
                        height: thumbnailHeight ?? displayedImageSize.height
                    )
                )
            } else if displayedImage == nil {
                // Keep the row stable while a refreshed capture is pending.
                // Preserve an existing captured glyph across a transient nil;
                // clearing and rebuilding it produced an avoidable blink.
                setFrameSize(Self.fallbackSize(for: item))
            }
            needsDisplay = true
        }
    }

    private var displayedImageRect: CGRect {
        CGRect(
            x: bounds.midX - (displayedImageSize.width / 2),
            y: (thumbnailHeight == nil ? bounds.midY : bounds.midY + 10) - (displayedImageSize.height / 2),
            width: displayedImageSize.width,
            height: displayedImageSize.height
        )
    }

    private var thumbnailHeight: CGFloat? { if #available(macOS 27.0, *) { 68 } else { nil } }
    private var thumbnailExtraWidth: CGFloat { if #available(macOS 27.0, *) { 12 } else { 0 } }

    private var thumbnailTitle: String {
        if item.tag.namespace == .controlCenter, item.tag.title == "com.apple.menuextra.wifi" {
            return "Wi-Fi"
        }
        return item.displayName
    }

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
            if isEnabled != oldValue { needsDisplay = true }
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState

        // Start with the same minimum slot used by captured glyphs so opening
        // Layout does not first publish one spacing and then snap to another.
        super.init(frame: CGRect(origin: .zero, size: Self.fallbackSize(for: item)))
        unregisterDraggedTypes()

        self.toolTip = item.displayName
        self.isEnabled = item.isMovable
        setAccessibilityElement(true)
        setAccessibilityLabel(item.displayName)
        setAccessibilityHelp("Drag to reorder this menu bar item")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(
                name: "Move Left"
            ) { [weak self] in
                self?.moveOnePosition(left: true) ?? false
            },
            NSAccessibilityCustomAction(
                name: "Move Right"
            ) { [weak self] in
                self?.moveOnePosition(left: false) ?? false
            },
            NSAccessibilityCustomAction(
                name: "Move to Hidden"
            ) { [weak self] in
                self?.move(toSection: .hidden) ?? false
            },
            NSAccessibilityCustomAction(
                name: "Move to Visible"
            ) { [weak self] in
                self?.move(toSection: .visible) ?? false
            },
        ])

        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.imageCache.$images
                .sink { [weak self] images in
                    guard let self else { return }
                    self.cachedImage = images[item.tag]
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Refreshes mutable Accessibility metadata while preserving the view and
    /// its captured image subscription. Recreating every item view whenever a
    /// menu bar frame changes produces a visible blink in the layout editor.
    func update(item: MenuBarItem) {
        precondition(self.item.tag == item.tag)
        self.item = item
        toolTip = item.displayName
        setAccessibilityLabel(item.displayName)
        isEnabled = item.isMovable
        if cachedImage == nil {
            setFrameSize(Self.fallbackSize(for: item))
        }
    }

    private static func fallbackSize(for item: MenuBarItem) -> CGSize {
        if #available(macOS 27.0, *) {
            CGSize(width: max(minimumItemWidth, item.bounds.width + 16), height: 68)
        } else {
            CGSize(width: max(minimumItemWidth, item.bounds.width), height: item.bounds.height)
        }
    }

    private func moveOnePosition(left: Bool) -> Bool {
        guard isEnabled, let appState else { return false }
        appState.menuBarManager.macOS27Controller.beginLayoutEditing()

        // Accessibility clients can deliver consecutive custom actions a few
        // hundred milliseconds apart. Debounce the complete burst into one
        // final displacement so crossing three icons performs one physical
        // read/write/verify transaction instead of three adjacent moves.
        pendingMoveOffset += left ? -1 : 1
        guard !pendingMoveIsExecuting else { return true }
        schedulePendingMove(using: appState)
        return true
    }

    /// Moves this item across an Ice section boundary. Besides making the
    /// Layout editor complete for VoiceOver users, this action exercises the
    /// same manager transaction as a cross-section AppKit drop.
    private func move(toSection section: MenuBarSection.Name) -> Bool {
        guard
            isEnabled,
            let appState,
            let address = appState.itemManager.itemCache.address(for: item.tag),
            address.section != section
        else {
            return false
        }

        let wasLayoutEditing = appState.menuBarManager.macOS27Controller.isLayoutEditing
        appState.menuBarManager.macOS27Controller.beginLayoutEditing()
        let freshItem = appState.itemManager.itemCache[address.section][address.index]
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            do {
                if !wasLayoutEditing {
                    // MenuBarAgent recreates concealed hosted scenes after the
                    // Layout reveals its native section boundaries. Give live AX
                    // endpoints one frame to return before resolving the move.
                    try? await Task.sleep(for: .milliseconds(160))
                }
                try await appState.itemManager.move(item: freshItem, toSection: section)
                appState.itemManager.removeTemporarilyShownItemFromCache(with: freshItem.tag)
            } catch {
                Logger.default.error("Error moving menu bar item between sections: \(error, privacy: .public)")
                NSAlert(error: error).runModal()
            }
        }
        return true
    }

    private func schedulePendingMove(using appState: AppState) {
        // A new action received during the quiet period restarts it. Do not
        // cancel an in-flight physical move; actions received while it runs
        // remain in pendingMoveOffset and are scheduled as the next burst.
        pendingMoveTask?.cancel()

        let itemTag = item.tag
        pendingMoveTask = Task { @MainActor [weak self, weak appState] in
            do {
                // One short run-loop-sized quiet window still coalesces rapid
                // accessibility actions, without making a single adjustment
                // feel like it was ignored before physical work begins.
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }

            guard let self, let appState, !Task.isCancelled else { return }
            pendingMoveIsExecuting = true
            let requestedOffset = pendingMoveOffset
            pendingMoveOffset = 0
            defer {
                pendingMoveIsExecuting = false
                pendingMoveTask = nil
                if pendingMoveOffset != 0 {
                    schedulePendingMove(using: appState)
                }
            }

            guard
                requestedOffset != 0,
                let address = appState.itemManager.itemCache.address(for: itemTag)
            else {
                return
            }

            let items = appState.itemManager.itemCache[address.section]
            let targetIndex = (address.index + requestedOffset).clamped(
                to: items.startIndex ... max(items.startIndex, items.endIndex - 1)
            )
            guard targetIndex != address.index else { return }

            let freshItem = items[address.index]
            let destination: MenuBarItemManager.MoveDestination = targetIndex < address.index
                ? .leftOfItem(items[targetIndex])
                : .rightOfItem(items[targetIndex])
            do {
                try await appState.itemManager.move(item: freshItem, to: destination)
            } catch {
                Logger.default.error("Error moving menu bar item: \(error, privacy: .public)")
            }
        }
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Menu bar item is not movable."
        alert.informativeText = "macOS prohibits \"\(item.displayName)\" from being moved."
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved."
        return alert
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            if #available(macOS 27.0, *) { drawThumbnailBackgroundAndLabel() }
            if displayedImageIsTemplate,
               let image = displayedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.clip(to: displayedImageRect, mask: image)
                context.setFillColor(NSColor.labelColor.withAlphaComponent(isEnabled ? 1 : 0.67).cgColor)
                context.fill(displayedImageRect)
                context.restoreGState()
            } else {
                displayedImage?.draw(
                    in: displayedImageRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: isEnabled ? 1.0 : 0.67
                )
            }
            if Bridging.isProcessUnresponsive(item.ownerPID) {
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

    @available(macOS 27.0, *)
    private func drawThumbnailBackgroundAndLabel() {
        if isHovered || isLocalDragActive {
            NSColor.labelColor.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }

        let preview = CGRect(
            x: bounds.midX - max(50, displayedImageSize.width + 12) / 2,
            y: bounds.midY - 7,
            width: max(50, displayedImageSize.width + 12),
            height: 34
        )
        if displayedImage == nil {
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: preview, xRadius: 7, yRadius: 7).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("…" as NSString).draw(in: preview.insetBy(dx: 4, dy: 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (thumbnailTitle as NSString).draw(
            in: CGRect(x: 4, y: 5, width: bounds.width - 8, height: 15),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .openHand) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        finishLocalDrag()
    }

    private func finishLocalDrag() {
        guard isLocalDragActive else { return }
        isLocalDragActive = false
        alphaValue = 1
        NSCursor.pop()
        localDropTarget?.clearLocalDropIndicator()
        localDropTarget = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard isEnabled else {
            let alert = provideAlertForDisabledItem()
            alert.runModal()
            return
        }

        guard !Bridging.isProcessUnresponsive(item.ownerPID) else {
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        if #available(macOS 27.0, *) {
            // Layout is a local editor: keep the source view in place until
            // mouse-up instead of juggling system drag-session exit callbacks.
            if !isLocalDragActive {
                isLocalDragActive = true
                window?.makeFirstResponder(self)
                alphaValue = 0.5
                NSCursor.closedHand.push()
                appState?.menuBarManager.macOS27Controller.beginLayoutEditing()
            }
            localDropTarget?.clearLocalDropIndicator()
            localDropTarget = window?.contentView.flatMap {
                LayoutBarPaddingView.localDropTarget(in: $0, at: event.locationInWindow)
            }
            localDropTarget?.showLocalDropIndicator(for: item, at: event.locationInWindow)
            return
        }

        // Data doesn't matter, but we do need to set the type.
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(displayedImageRect, contents: displayedImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard isLocalDragActive else {
            super.mouseUp(with: event)
            return
        }
        if let root = window?.contentView,
           let target = LayoutBarPaddingView.localDropTarget(in: root, at: event.locationInWindow) {
            target.acceptLocalDrop(item: item, at: event.locationInWindow)
        }
        finishLocalDrag()
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        appState?.menuBarManager.macOS27Controller.beginLayoutEditing()
        dragSessionGeneration &+= 1
        didAcceptCurrentDrop = false
        isDragSessionActive = true

        // Capture the origin before the first drag update. A fast long drag can
        // leave the padding view before AppKit sends `draggingUpdated`, and the
        // old lazy capture then had no container/index with which to restore a
        // cancelled drop. That made the tile disappear until Layout reopened.
        if let container = superview as? LayoutBarContainer {
            if
                oldContainerInfo == nil,
                let index = container.arrangedViews.firstIndex(of: self)
            {
                oldContainerInfo = (container, index)
            }

            // Make sure the container doesn't update its arranged views while
            // the drag's provisional order is being displayed.
            container.canSetArrangedViews = false
        }

        // prevent the dragging image from animating back to its original location
        session.animatesToStartingPositionsOnCancelOrFail = false

        // async to prevent the view from disappearing before the dragging image appears
        DispatchQueue.main.async {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let originalInfo = oldContainerInfo
        let sessionGeneration = dragSessionGeneration
        isDragSessionActive = false

        // since the session's `animatesToStartingPositionsOnCancelOrFail` property was
        // set to false when the session began (above), there is no delay between the user
        // releasing the dragging item and this method being called; thus, `isDraggingPlaceholder`
        // only needs to be updated here; if we ever decide we want animation, it may also
        // need to be updated inside `performDragOperation(_:)` on `LayoutBarPaddingView`
        isDraggingPlaceholder = false

        // Do not restore synchronously here. On macOS 27 AppKit may call this
        // source method before the destination's `performDragOperation`, then
        // send one final `draggingExited`. Rebuilding the old order now would
        // overwrite the valid drop's immediate preview.
        let isArrangedInSuperview = (superview as? LayoutBarContainer)?.arrangedViews.contains {
            $0 === self
        } == true
        if isArrangedInSuperview {
            hasContainer = true
        }

        // Fifty milliseconds is long enough for the destination callback to
        // set `didAcceptCurrentDrop`, while keeping a genuinely cancelled tile
        // from being absent for a visible interval. The generation guard keeps
        // an unusually fast next drag from being modified by this cleanup.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard
                let self,
                self.dragSessionGeneration == sessionGeneration
            else {
                return
            }

            if !self.didAcceptCurrentDrop, let originalInfo {
                let originalContainer = originalInfo.container
                var views = originalContainer.arrangedViews
                views.removeAll { $0 === self || $0.item.tag == self.item.tag }
                views.insert(self, at: min(originalInfo.index, views.endIndex))
                originalContainer.arrangedViews = views
                self.hasContainer = true
            }

            if !self.isAwaitingPhysicalMove {
                originalInfo?.container.canSetArrangedViews = true
            }
            self.oldContainerInfo = nil
            self.didAcceptCurrentDrop = false
        }
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem { }

// MARK: Layout Bar Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
