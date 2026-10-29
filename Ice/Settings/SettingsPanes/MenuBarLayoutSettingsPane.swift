//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var hasScreenRecordingPermission = ScreenCapture.cachedCheckPermissions()
    @State private var hasAccessibilityPermission = MenuBarItemAXDiscovery.isTrusted()
    @State private var sections = [MenuBarItemAXDiscovery.SectionKind: [RowItem]]()
    @State private var hiddenDividerX: CGFloat?
    @State private var alwaysHiddenDividerX: CGFloat?
    @State private var anchorY: CGFloat = 0
    /// Guards against overlapping Refreshes: stacked AX + CGS scans cause stutter.
    @State private var isRefreshing = false
    /// Guards against overlapping drags: two concurrent Command-drags would fight over the mouse.
    @State private var isMoving = false
    /// IDs of icons currently being moved in the background: the UI updates
    /// optimistically right away, with a small badge on each icon showing
    /// it's syncing, so the whole list doesn't freeze.
    @State private var pendingMoves = Set<String>()
    /// Icon hovered during a drag: the blue outline shows dropping here inserts
    /// before it. Also lets the section know this drop already has an item
    /// handling it (so item and section don't both handle the same drop).
    @State private var dropTargetID: String?
    /// Generation counter for the divider poll: a new scan bumps it to cancel
    /// the previous poll, so only the latest scan keeps polling.
    @State private var dividerPollGeneration = 0
    /// App icons by PID: `NSRunningApplication.icon` is nil transiently on
    /// first lookup (app info not loaded yet) → gray box until the next
    /// Refresh. Caching successes keeps icons stable across re-classifies,
    /// and the retry below fills misses without manual taps.
    @State private var iconCache = [pid_t: NSImage]()
    /// Generation for the missing-icon retry: a new scan bumps it to cancel
    /// the previous retry, so only the latest scan keeps retrying.
    @State private var iconRetryGeneration = 0
    /// Why the last move didn't happen, shown under the header so a failed
    /// drag no longer just snaps back without a word.
    @State private var moveMessage: String?

    private var totalCount: Int {
        sections.values.reduce(0) { $0 + $1.count }
    }

    /// Displayed groups: with "Enable always-hidden section" off in
    /// Advanced, the Always Hidden group stays hidden here too.
    private var visibleMetas: [SectionMeta] {
        if appState.settingsManager.advancedSettingsManager.enableAlwaysHiddenSection {
            SectionMeta.all
        } else {
            SectionMeta.all.filter { $0.kind != .alwaysHidden }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Menu Bar Icons")
                    .font(.title)
                Text("\(totalCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())

                Spacer()

                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(IceButtonStyle())
                .disabled(isRefreshing)
            }

            if let moveMessage {
                Label(moveMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if sections.isEmpty {
                if !hasAccessibilityPermission {
                    accessibilityPrompt
                } else if !hasScreenRecordingPermission {
                    permissionPrompt
                } else if appState.itemManager.isItemDiscoveryUnavailable {
                    discoveryUnavailable
                } else {
                    ContentUnavailableView(
                        "No menu bar items",
                        systemImage: "rectangle.topthird.inset.filled",
                        description: Text("Waiting for menu bar items to appear…")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(visibleMetas, id: \.kind) { meta in
                            sectionView(meta: meta, items: sections[meta.kind] ?? [])
                        }
                        if hiddenDividerX == nil, alwaysHiddenDividerX == nil {
                            Text("Can't find Ice's section dividers — make sure the Hidden sections are enabled, then press Refresh.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .task {
            // Paint immediately from the available cache (the 5s background timer
            // keeps pumping itemCache), then reconcile with a background scan —
            // opening the tab shows icons right away, no Refresh tap needed.
            applySnapshotFromCache()
            await refresh()
            if #available(macOS 27, *) {
                // Opening this pane reveals every section (MenuBarManager's
                // layout editing); scan again once the icons have settled so
                // hidden ones show real positions.
                try? await Task.sleep(for: .milliseconds(800))
                await refresh()
            }
        }
        .onReceive(appState.itemManager.$itemCache) { _ in
            // When the cache changes (background timer, newly opened app,
            // finished drag), the UI follows. While dragging, keep the
            // optimistic UI and let reconcile overwrite it.
            guard !isMoving else {
                return
            }
            applySnapshotFromCache()
        }
        .onDisappear {
            // Stop the divider poll + icon retry when leaving the tab.
            dividerPollGeneration += 1
            iconRetryGeneration += 1
        }
    }

    private func sectionView(meta: SectionMeta, items: [RowItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: meta.icon)
                Text(meta.title)
                    .font(.headline)
                Text(meta.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                // Dashed "New" cell at the head of the Visible group: where newly
                // appeared icons land, matching the mock (right-aligned, so it sits leftmost).
                if meta.kind == .visible {
                    newItemPlaceholder
                }
                if items.isEmpty {
                    Text(meta.emptyHint)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(items) { item in
                        itemView(item, pending: pendingMoves.contains(item.id), isDropTarget: dropTargetID == item.id)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onDrop(of: [.text], isTargeted: .constant(false), perform: { providers in
                // When hovering an icon, let that item handle the drop (positional
                // insert); the section only handles drops into empty space (append to the group's end).
                guard dropTargetID == nil, !isMoving, let provider = providers.first else {
                    return false
                }
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let id = string as? String else {
                        return
                    }
                    Task { @MainActor in
                        await drop(itemID: id, to: meta.kind)
                    }
                }
                return true
            })
        }
    }

    private func itemView(_ item: RowItem, pending: Bool, isDropTarget: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let systemName = item.systemImage {
                        Image(systemName: systemName)
                            .font(.system(size: 17))
                            .frame(width: 40, height: 30)
                    } else if let icon = item.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .frame(width: 40, height: 30)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 40, height: 30)
                    }
                }
                // System icons (com.apple.* bundles) get an extra Apple logo badge
                // at the top-right corner for distinction, as in the mock.
                if item.isSystem {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 14, height: 14)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 68)
        }
        .frame(width: 68)
        .help(pending ? "\(item.subtitle ?? item.title) — đang di chuyển…" : (item.subtitle ?? item.title))
        .opacity(pending ? 0.7 : 1)
        .overlay {
            // Blue outline on drag hover: releasing inserts before this icon.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDropTarget ? .blue : .clear, lineWidth: 2)
                .frame(width: 52, height: 56)
        }
        .overlay(alignment: .topTrailing) {
            if pending {
                ProgressView()
                    .controlSize(.mini)
                    .padding(4)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
        .onDrag {
            NSItemProvider(object: item.id as NSString)
        }
        .onDrop(
            of: [.text],
            isTargeted: dropTargetBinding(for: item.id),
            perform: { providers in
                guard !isMoving, let provider = providers.first else {
                    return false
                }
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let id = string as? String else {
                        return
                    }
                    Task { @MainActor in
                        await drop(itemID: id, onto: item.id)
                    }
                }
                return true
            }
        )
    }

    /// Hover binding for one icon: dragging over it shows the blue outline, and
    /// the section yields this drop to the item (positional insert instead of appending to the group's end).
    private func dropTargetBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { dropTargetID == id },
            set: { targeted in
                if targeted {
                    dropTargetID = id
                } else if dropTargetID == id {
                    dropTargetID = nil
                }
            }
        )
    }

    /// Dashed "New" cell at the head of the Visible group: where newly appeared icons land.
    private var newItemPlaceholder: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: 40, height: 30)
                .overlay {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            Text("New")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 68)
        }
        .frame(width: 68)
        .help("New menu bar items appear here")
    }

    /// Drop an item into a new group: each attempt re-reads live positions
    /// first (cached frames go stale — a drag changes no window IDs, so a
    /// plain re-scan would reuse pre-drag frames), drags, then verifies the
    /// icon really landed before counting it. Up to 3 physical drags; between
    /// attempts the UI rebuilds from truth, so a miss never leaves a fake
    /// optimistic position behind.
    /// The `isMoving` guard blocks a second drag from fighting over the mouse.
    private func drop(itemID: String, to kind: MenuBarItemAXDiscovery.SectionKind) async {
        guard !isMoving else {
            return
        }
        isMoving = true
        moveMessage = nil
        pendingMoves.insert(itemID)
        defer {
            pendingMoves.remove(itemID)
            isMoving = false
        }
        for _ in 0..<3 {
            // Live positions, not the last scan: on macOS 27 the item cache
            // is empty and the stored frames go stale as soon as anything moves.
            await rescanLive()
            let snapshotBeforeDrag = sections
            guard let (item, fromKind) = removeItem(id: itemID) else {
                await refresh()
                return
            }
            guard fromKind != kind else {
                // Already in the destination group; put it back where it was,
                // then re-scan so the UI is truth, not the optimistic append.
                sections[kind, default: []].append(item)
                pendingMoves.remove(itemID)
                isMoving = false
                await refreshAfterDrop()
                return
            }
            guard
                let destination = destinationPoint(for: kind),
                let sourceFrame = item.quartzFrame
            else {
                // No drop target known — re-scan for the real positions.
                sections = snapshotBeforeDrag
                moveMessage = "Couldn't find Ice's section dividers in the menu bar. Make sure they're enabled, then try again."
                await refresh()
                return
            }
            guard await isReachable(item) else {
                sections = snapshotBeforeDrag
                moveMessage = unreachableMessage(for: item)
                await refreshAfterDrop()
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                sections[kind, default: []].append(item)
            }
            await MenuBarItemAXMover.commandDrag(
                from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                to: destination
            )
            sections = snapshotBeforeDrag
            await rescanLive()
            if sections[kind]?.contains(where: { $0.id == itemID }) == true {
                // Landed — but the frame right after a drag can still be
                // settling, so always do one settled re-scan instead of
                // trusting this snapshot. Otherwise the UI sometimes stays
                // wrong until the user hits Refresh by hand.
                pendingMoves.remove(itemID)
                isMoving = false
                await refreshAfterDrop()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        pendingMoves.remove(itemID)
        isMoving = false
        moveMessage = "macOS didn't accept the move. Try ⌘-dragging the icon in the menu bar instead."
        await refreshAfterDrop()
    }

    /// Remove the item from its current group, returning the item and its old group.
    private func removeItem(id: String) -> (RowItem, MenuBarItemAXDiscovery.SectionKind)? {
        guard let found = findItem(id: id) else {
            return nil
        }
        var updated = sections[found.kind] ?? []
        updated.remove(at: found.index)
        sections[found.kind] = updated
        return (found.item, found.kind)
    }

    /// Find an item by stable ID, returning the item + group + index within the group
    /// (groups are already ordered left-to-right as on the menu bar).
    private func findItem(id: String) -> (item: RowItem, kind: MenuBarItemAXDiscovery.SectionKind, index: Int)? {
        for (kind, items) in sections {
            if let index = items.firstIndex(where: { $0.id == id }) {
                return (items[index], kind, index)
            }
        }
        return nil
    }

    /// Drop one icon onto another: insert before the target icon (same zone
    /// means reordering, different zone means moving zones at the right position).
    /// Like section drops, each attempt re-reads live positions first, drags,
    /// then verifies the landing — a missed drag is retried with fresh frames
    /// instead of snapping back and forcing the user to redo it by hand.
    private func drop(itemID: String, onto targetID: String) async {
        guard !isMoving else {
            return
        }
        guard itemID != targetID else {
            return
        }
        isMoving = true
        moveMessage = nil
        pendingMoves.insert(itemID)
        defer {
            pendingMoves.remove(itemID)
            isMoving = false
            dropTargetID = nil
        }
        for _ in 0..<3 {
            await rescanLive()
            guard
                let (item, fromKind, fromIndex) = findItem(id: itemID),
                let target = findItem(id: targetID),
                let sourceFrame = item.quartzFrame
            else {
                await refresh()
                return
            }
            let toKind = target.kind
            if fromKind == toKind, isImmediatelyBefore(itemID: itemID, targetID: targetID, in: toKind) {
                // Already in position — no drag needed.
                return
            }
            guard await isReachable(item) else {
                moveMessage = unreachableMessage(for: item)
                await refreshAfterDrop()
                return
            }
            let snapshotBeforeDrag = sections
            // Remove the source first, then compute the insert position after
            // compaction (dragging forward shifts the target index down by 1 because the array is now shorter).
            var withoutSource = sections[fromKind] ?? []
            withoutSource.remove(at: fromIndex)
            sections[fromKind] = withoutSource
            let toItems = sections[toKind] ?? []
            let insertIndex: Int
            if fromKind == toKind, fromIndex < target.index {
                insertIndex = target.index - 1
            } else {
                insertIndex = toItems.firstIndex(where: { $0.id == targetID }) ?? toItems.count
            }
            let leftFrame = insertIndex > 0 ? toItems[max(0, insertIndex - 1)].quartzFrame : nil
            let rightFrame = insertIndex < toItems.count ? toItems[insertIndex].quartzFrame : nil
            guard let destination = reorderDestination(for: toKind, leftFrame: leftFrame, rightFrame: rightFrame) else {
                await refresh()
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                sections[toKind, default: []].insert(item, at: min(insertIndex, toItems.count))
            }
            await MenuBarItemAXMover.commandDrag(
                from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                to: destination
            )
            sections = snapshotBeforeDrag
            await rescanLive()
            if hasLanded(itemID: itemID, targetID: targetID, fromKind: fromKind, toKind: toKind) {
                // Same as section drops: one settled re-scan after landing,
                // don't trust the immediate post-drag snapshot.
                pendingMoves.remove(itemID)
                isMoving = false
                dropTargetID = nil
                await refreshAfterDrop()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        pendingMoves.remove(itemID)
        isMoving = false
        dropTargetID = nil
        moveMessage = "macOS didn't accept the move. Try ⌘-dragging the icon in the menu bar instead."
        await refreshAfterDrop()
    }

    /// Whether a drag can start on the item: its frame must be a real spot
    /// on a menu bar, and that spot must actually show this app's item.
    ///
    /// On a crowded notched screen macOS parks icons that don't fit in
    /// overflow, where Accessibility still reports a frame on top of other
    /// icons. A hit test tells them apart.
    private func isReachable(_ item: RowItem) async -> Bool {
        guard let frame = item.quartzFrame, frame.width > 0, frame.height > 0 else {
            return false
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { screen in
            let bounds = CGDisplayBounds(screen.displayID)
            return bounds.contains(center) && center.y - bounds.minY < 50
        }) else {
            return false
        }
        if let rightArea = screen.auxiliaryTopRightArea, center.x < rightArea.minX {
            // Status items only live right of the notch.
            return false
        }
        guard let pid = item.pid else {
            return true
        }
        // Off the main thread: if the point lands on one of Ice's own items,
        // the request is answered by this process.
        let hitPID: pid_t? = await Task.detached(priority: .userInitiated) {
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 1)
            var element: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(systemWide, Float(center.x), Float(center.y), &element)
            guard result == .success, let element else {
                return nil
            }
            var hitPID: pid_t = 0
            AXUIElementGetPid(element, &hitPID)
            return hitPID
        }.value
        // No answer is not proof of absence; let the drag try.
        return hitPID.map { $0 == pid } ?? true
    }

    /// Explains why an icon can't be dragged right now.
    private func unreachableMessage(for item: RowItem) -> String {
        "“\(item.title)” isn't visible in the menu bar right now (it may be hidden behind the notch), "
            + "so it can't be dragged. Make room by quitting an app with a menu bar icon, then try again."
    }

    /// True when the item already sits immediately before the target in its group.
    private func isImmediatelyBefore(itemID: String, targetID: String, in kind: MenuBarItemAXDiscovery.SectionKind) -> Bool {
        guard
            let items = sections[kind],
            let itemIndex = items.firstIndex(where: { $0.id == itemID }),
            let targetIndex = items.firstIndex(where: { $0.id == targetID })
        else {
            return false
        }
        return itemIndex + 1 == targetIndex
    }

    /// True when a drag verifiably landed: cross-zone means membership in the
    /// destination group, same-zone means sitting right before the target icon.
    private func hasLanded(
        itemID: String,
        targetID: String,
        fromKind: MenuBarItemAXDiscovery.SectionKind,
        toKind: MenuBarItemAXDiscovery.SectionKind
    ) -> Bool {
        guard let items = sections[toKind] else {
            return false
        }
        guard items.contains(where: { $0.id == itemID }) else {
            return false
        }
        if fromKind == toKind {
            return isImmediatelyBefore(itemID: itemID, targetID: targetID, in: toKind)
        }
        return true
    }

    /// Command-drag drop point for inserting into the gap between two adjacent
    /// frames (Quartz coordinates): mid-gap when both exist, 12pt offset from
    /// the edge at the ends. Clamped inside the zone bounds when the dividers
    /// are known, so the drop can't fall into another zone.
    private func reorderDestination(
        for kind: MenuBarItemAXDiscovery.SectionKind,
        leftFrame: CGRect?,
        rightFrame: CGRect?
    ) -> CGPoint? {
        let y = anchorY == 0 ? 8 : anchorY
        if let left = leftFrame, let right = rightFrame {
            if left.maxX < right.minX {
                return CGPoint(x: (left.maxX + right.minX) / 2, y: y)
            }
            return CGPoint(x: (left.midX + right.midX) / 2, y: y)
        }
        if let right = rightFrame {
            var x = right.minX - 12
            if let bound = leftBound(for: kind), x < bound + 6 {
                x = bound + 10
            }
            return CGPoint(x: x, y: y)
        }
        if let left = leftFrame {
            var x = left.maxX + 12
            if let bound = rightBound(for: kind), x > bound - 6 {
                x = bound - 10
            }
            return CGPoint(x: x, y: y)
        }
        return destinationPoint(for: kind)
    }

    /// Left bound of the zone (minX of the divider on the left), nil when unknown.
    private func leftBound(for kind: MenuBarItemAXDiscovery.SectionKind) -> CGFloat? {
        switch kind {
        case .visible:
            hiddenDividerX ?? alwaysHiddenDividerX
        case .hidden:
            alwaysHiddenDividerX
        case .alwaysHidden:
            nil
        }
    }

    /// Right bound of the zone (minX of the divider on the right), nil when unknown.
    private func rightBound(for kind: MenuBarItemAXDiscovery.SectionKind) -> CGFloat? {
        switch kind {
        case .visible:
            nil
        case .hidden:
            hiddenDividerX
        case .alwaysHidden:
            alwaysHiddenDividerX ?? hiddenDividerX
        }
    }

    /// Command-drag drop point for the destination group (Quartz coordinates,
    /// top-left origin, same system as `CGEvent`).
    ///
    /// Hidden groups drop just left of their divider's edge: that slot is in
    /// the group whether it is empty or not. Dropping halfway to the next
    /// divider used to hit the middle of the always-hidden chevron when the
    /// Hidden group was empty, and 24pt out could hit bare menu bar.
    private func destinationPoint(for kind: MenuBarItemAXDiscovery.SectionKind) -> CGPoint? {
        switch kind {
        case .visible:
            guard let x = hiddenDividerX ?? alwaysHiddenDividerX else {
                return nil
            }
            return CGPoint(x: x + 40, y: anchorY)
        case .hidden:
            guard let x = hiddenDividerX else {
                return nil
            }
            return CGPoint(x: x - 4, y: anchorY)
        case .alwaysHidden:
            guard let x = alwaysHiddenDividerX else {
                return nil
            }
            return CGPoint(x: x - 4, y: anchorY)
        }
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 12) {
            Text("Menu bar layout requires accessibility permission")
                .font(.title2)
            Text("Grant Accessibility access so Ice can list the icons in your menu bar.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Open System Settings") {
                    openURL(Self.accessibilitySettingsURL)
                }
                Button("Check Again") {
                    Task {
                        await refresh()
                    }
                }
            }
            .buttonStyle(IceButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 12) {
            Text("Menu bar layout requires screen recording permission")
                .font(.title2)
            Text("Grant Screen Recording access so Ice can see the icons in your menu bar.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Open System Settings") {
                    openURL(Self.screenRecordingSettingsURL)
                }
                Button("Check Again") {
                    Task {
                        await refresh()
                    }
                }
            }
            .buttonStyle(IceButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var discoveryUnavailable: some View {
        VStack(spacing: 12) {
            Text("Menu Bar Layout isn't available on this macOS version")
                .font(.title2)
            Text("This version of macOS no longer exposes individual menu bar items to Ice.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Manual scan from the Refresh button: shows the spinner, blocks overlapping taps.
    private func refresh() async {
        // Guard against overlapping scans when Refresh is tapped repeatedly.
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
        }
        await scanAndApply()
    }

    /// Settled re-scan after a drag: unlike the Refresh button it must never
    /// be skipped by the `isRefreshing` guard (e.g. the tab-open scan still
    /// running), otherwise the UI stays on the pre-drag snapshot until the
    /// user hits Refresh by hand.
    private func refreshAfterDrop() async {
        for _ in 0..<30 where isRefreshing {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if isRefreshing {
            // A scan is stuck (divider wait); run one anyway so the post-drag
            // truth is painted instead of leaving the optimistic UI behind.
            await scanAndApply()
        } else {
            await refresh()
        }
    }

    /// Rebuild live truth without trusting the optimistic SwiftUI state.
    ///
    /// Runs before every drag (to start from where the icon really is) and
    /// after it (to verify the landing). macOS 27 clears the CGS item cache
    /// because per-item windows are gone, so an AX scan is the only real
    /// source of fresh frames and membership.
    private func rescanLive() async {
        await appState.itemManager.cacheItemsIfNeeded(force: true)
        let (hiddenX, alwaysHiddenX) = resolveDividers()
        hiddenDividerX = hiddenX
        alwaysHiddenDividerX = alwaysHiddenX

        var axFallback = [MenuBarItemAXDiscovery.AXMenuBarItem]()
        if appState.itemManager.itemCache.allItems.isEmpty, MenuBarItemAXDiscovery.isTrusted() {
            let apps = NSWorkspace.shared.runningApplications
            axFallback = await Task.detached(priority: .userInitiated) {
                MenuBarItemAXDiscovery.discoverItems(in: apps)
            }.value
        }
        let (grouped, midY) = buildSections(
            hiddenX: hiddenX,
            alwaysHiddenX: alwaysHiddenX,
            axFallback: axFallback
        )
        if !grouped.isEmpty {
            sections = grouped
        }
        if let midY {
            anchorY = midY
        }
    }

    /// Fast synchronous divider read: prefers AX (own process, no system-wide
    /// walk), falls back to window.frame when AX isn't available yet.
    /// Same approach Ice Bar uses to avoid junk frames from the offscreen spacer park.
    private func resolveDividers() -> (hiddenX: CGFloat?, alwaysHiddenX: CGFloat?) {
        let axDividers = MenuBarItemAXDiscovery.dividerFrames()
        func settledMinX(_ frame: CGRect?) -> CGFloat? {
            frame.flatMap { MenuBarItemAXDiscovery.isSettledDividerFrame($0) ? $0.minX : nil }
        }
        func saneMinX(_ value: CGFloat?) -> CGFloat? {
            value.flatMap { $0 > 0 ? $0 : nil }
        }
        let manager = appState.menuBarManager
        let rawHiddenX = settledMinX(axDividers.hidden)
            ?? saneMinX(manager.section(withName: .hidden)?.controlItem.window?.frame.minX)
        let rawAlwaysHiddenX = settledMinX(axDividers.alwaysHidden)
            ?? saneMinX(manager.section(withName: .alwaysHidden)?.controlItem.window?.frame.minX)
        let dividers = MenuBarItemAXDiscovery.normalizedDividers(
            hiddenDividerX: rawHiddenX,
            alwaysHiddenDividerX: rawAlwaysHiddenX
        )
        return (dividers.hidden, dividers.alwaysHidden)
    }

    /// Build sections from the available CGS cache + current dividers, without scanning.
    /// Called synchronously when opening the tab and when $itemCache changes so the UI appears immediately.
    private func applySnapshotFromCache() {
        hasAccessibilityPermission = MenuBarItemAXDiscovery.isTrusted()
        let (hiddenX, alwaysHiddenX) = resolveDividers()
        hiddenDividerX = hiddenX
        alwaysHiddenDividerX = alwaysHiddenX
        let (grouped, midQuartzY) = buildSections(
            hiddenX: hiddenX,
            alwaysHiddenX: alwaysHiddenX,
            axFallback: []
        )
        // Cache still empty (fresh boot, timer hasn't pumped yet): keep the old
        // sections so the UI doesn't flash back to the placeholder; the background scan will fill it in.
        if !grouped.isEmpty {
            sections = grouped
        }
        if let midQuartzY {
            anchorY = midQuartzY
        } else if anchorY == 0 {
            anchorY = 8
        }
    }

    /// Build icon groups from the CGS cache in true menu bar order (left-to-right
    /// by center X). Returns the groups + mid-Y to use as the Command-drag drop point.
    private func buildSections(
        hiddenX: CGFloat?,
        alwaysHiddenX: CGFloat?,
        axFallback: [MenuBarItemAXDiscovery.AXMenuBarItem]
    ) -> (grouped: [MenuBarItemAXDiscovery.SectionKind: [RowItem]], midQuartzY: CGFloat?) {
        func kind(centerX: CGFloat?) -> MenuBarItemAXDiscovery.SectionKind {
            MenuBarItemAXDiscovery.classify(centerX: centerX, hiddenDividerX: hiddenX, alwaysHiddenDividerX: alwaysHiddenX)
        }
        var idCounts = [String: Int]()
        func stableID(for base: String) -> String {
            let n = idCounts[base, default: 0]
            idCounts[base] = n + 1
            return n == 0 ? base : "\(base)#\(n)"
        }
        let ownBundleID = Bundle.main.bundleIdentifier
        var grouped = [MenuBarItemAXDiscovery.SectionKind: [RowItem]]()
        var quartzYs = [CGFloat]()
        // Both CGS and AX sort by ascending center X = left-to-right on the menu
        // bar, matching the real-world order with Clock at the far right.
        let cached = appState.itemManager.itemCache.allItems
            .filter { $0.owningApplication?.bundleIdentifier != ownBundleID }
            .sorted { $0.frame.midX < $1.frame.midX }
        if !cached.isEmpty {
            for item in cached {
                quartzYs.append(item.frame.midY)
                // Single lookup: owningApplication builds a new
                // NSRunningApplication each access, and .icon is nil
                // transiently on first touch — reuse + cache it.
                let app = item.owningApplication
                let bundleID = app?.bundleIdentifier
                let systemImage = MenuBarItemAXDiscovery.systemImageName(
                    forTitle: item.title ?? item.displayName, bundleID: bundleID
                )
                var appIcon: NSImage?
                if systemImage == nil {
                    if let cachedIcon = iconCache[item.ownerPID] {
                        appIcon = cachedIcon
                    } else if let icon = app?.icon {
                        iconCache[item.ownerPID] = icon
                        appIcon = icon
                    }
                }
                grouped[kind(centerX: item.frame.midX), default: []].append(
                    RowItem(
                        id: stableID(for: "cgs:\(item.info):\(item.ownerPID)"),
                        title: item.displayName,
                        subtitle: item.subtitle,
                        systemImage: systemImage,
                        appIcon: appIcon,
                        isSystem: bundleID?.hasPrefix("com.apple.") == true,
                        quartzFrame: item.frame,
                        pid: item.ownerPID
                    )
                )
            }
        } else {
            for item in axFallback.sorted(by: { ($0.axFrame?.midX ?? .greatestFiniteMagnitude) < ($1.axFrame?.midX ?? .greatestFiniteMagnitude) }) {
                let systemImage = MenuBarItemAXDiscovery.systemImageName(forIdentifier: item.identifier)
                var appIcon: NSImage?
                if systemImage == nil {
                    if let cachedIcon = iconCache[item.pid] {
                        appIcon = cachedIcon
                    } else if item.bundleID == "com.apple.TextInputMenuAgent" {
                        if let icon = MenuBarItemAXDiscovery.inputSourceIcon() {
                            iconCache[item.pid] = icon
                            appIcon = icon
                        }
                    } else if let icon = NSRunningApplication(processIdentifier: item.pid)?.icon {
                        iconCache[item.pid] = icon
                        appIcon = icon
                    }
                }
                if let frame = item.axFrame {
                    quartzYs.append(frame.midY)
                }
                grouped[kind(centerX: item.axFrame?.midX), default: []].append(
                    RowItem(
                        id: stableID(for: "ax:\(item.pid):\(item.bundleID ?? ""):\(item.identifier ?? ""):\(item.title ?? "")"),
                        title: item.displayName,
                        subtitle: item.subtitle,
                        systemImage: systemImage,
                        appIcon: appIcon,
                        isSystem: item.bundleID?.hasPrefix("com.apple.") == true,
                        quartzFrame: item.axFrame,
                        pid: item.pid
                    )
                )
            }
        }
        let midY: CGFloat? = quartzYs.isEmpty ? nil : quartzYs.sorted()[quartzYs.count / 2]
        return (grouped, midY)
    }

    /// Whether Ice's Hidden divider is expected in the menu bar right now.
    private func isHiddenDividerExpected() -> Bool {
        appState.menuBarManager.section(withName: .hidden)?.controlItem.isAddedToMenuBar == true
    }

    /// Whether Ice's Always Hidden divider is expected in the menu bar right now.
    private func isAlwaysHiddenDividerExpected() -> Bool {
        guard appState.settingsManager.advancedSettingsManager.enableAlwaysHiddenSection else {
            return false
        }
        return appState.menuBarManager.section(withName: .alwaysHidden)?.controlItem.isAddedToMenuBar == true
    }

    /// True when an expected divider's position is still unknown — icons would
    /// be misclassified until it appears. Checks each divider independently so
    /// a late second divider doesn't get stuck when the first one is already known.
    private func isMissingExpectedDivider(hiddenX: CGFloat?, alwaysHiddenX: CGFloat?) -> Bool {
        (hiddenX == nil && isHiddenDividerExpected())
            || (alwaysHiddenX == nil && isAlwaysHiddenDividerExpected())
    }

    /// Keep re-classifying from the current cache until expected dividers show
    /// up (up to ~7s). Lightweight: only re-reads divider positions, no CGS
    /// walk — the 5s background timer keeps pumping itemCache separately.
    private func startDividerPoll() {
        dividerPollGeneration += 1
        let generation = dividerPollGeneration
        Task { @MainActor in
            for _ in 0..<14 {
                try? await Task.sleep(for: .milliseconds(500))
                guard generation == dividerPollGeneration else {
                    return
                }
                if isMoving {
                    continue
                }
                let (hx, ahx) = resolveDividers()
                if hx != hiddenDividerX || ahx != alwaysHiddenDividerX {
                    hiddenDividerX = hx
                    alwaysHiddenDividerX = ahx
                    applySnapshotFromCache()
                }
                if !isMissingExpectedDivider(hiddenX: hx, alwaysHiddenX: ahx) {
                    return
                }
            }
        }
    }

    /// One real scan: read permissions, CGS cache, classify by dividers.
    private func scanAndApply() async {
        // Cancel any previous divider poll + icon retry; this scan starts its own if needed.
        dividerPollGeneration += 1
        iconRetryGeneration += 1
        // With permission already granted, use the cache instead of making
        // WindowServer walk the window list again on every Refresh.
        if !hasScreenRecordingPermission {
            hasScreenRecordingPermission = ScreenCapture.cachedCheckPermissions(reset: true)
        }
        hasAccessibilityPermission = MenuBarItemAXDiscovery.isTrusted()
        // Paint a temporary frame from the old cache first so the screen doesn't go blank while waiting.
        applySnapshotFromCache()
        if hasScreenRecordingPermission {
            await appState.itemManager.cacheItemsIfNeeded()
        }

        // Dividers have no window right after boot → minX is nil → every icon
        // would be misclassified as Visible. Prefer fast AX, waiting at most ~2s
        // when an expected divider is still missing, instead of making the user hit Refresh repeatedly.
        var (hiddenX, alwaysHiddenX) = resolveDividers()
        if isMissingExpectedDivider(hiddenX: hiddenX, alwaysHiddenX: alwaysHiddenX) {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                (hiddenX, alwaysHiddenX) = resolveDividers()
                if !isMissingExpectedDivider(hiddenX: hiddenX, alwaysHiddenX: alwaysHiddenX) {
                    break
                }
            }
        }
        hiddenDividerX = hiddenX
        alwaysHiddenDividerX = alwaysHiddenX

        var axFallback = [MenuBarItemAXDiscovery.AXMenuBarItem]()
        if appState.itemManager.itemCache.allItems.isEmpty, hasAccessibilityPermission {
            let apps = NSWorkspace.shared.runningApplications
            axFallback = await Task.detached(priority: .userInitiated) {
                MenuBarItemAXDiscovery.discoverItems(in: apps)
            }.value
        }
        let (grouped, midY) = buildSections(hiddenX: hiddenX, alwaysHiddenX: alwaysHiddenX, axFallback: axFallback)
        if !grouped.isEmpty {
            sections = grouped
        }
        if let midY {
            anchorY = midY
        } else if anchorY == 0 {
            anchorY = 8
        }

        // When an expected divider's window hasn't appeared yet, keep polling
        // so the icons land in the right groups without manual Refresh taps.
        if isMissingExpectedDivider(hiddenX: hiddenX, alwaysHiddenX: alwaysHiddenX), !grouped.isEmpty {
            startDividerPoll()
        }

        // Icons that are still blank (app icon nil on first lookup) fill in
        // on their own — no repeated Refresh taps needed. Pass the AX
        // fallback through: when the CGS cache is empty the retry must
        // rebuild from the same AX items (applySnapshotFromCache alone
        // would rebuild from an empty cache with no fallback and change nothing).
        scheduleIconRetryIfNeeded(axFallback: axFallback)
    }

    /// Re-resolve blank icons a couple times: `NSRunningApplication.icon`
    /// is often nil on first touch right after opening the tab. Retries only
    /// re-read icons/dividers from the current cache (no CGS walk), so they
    /// are cheap; a new scan cancels the previous retry.
    private func scheduleIconRetryIfNeeded(axFallback: [MenuBarItemAXDiscovery.AXMenuBarItem] = []) {
        guard sections.values.flatMap({ $0 }).contains(where: { $0.systemImage == nil && $0.appIcon == nil }) else {
            return
        }
        iconRetryGeneration += 1
        let generation = iconRetryGeneration
        Task { @MainActor in
            for delay in [500, 1500] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard generation == iconRetryGeneration, !isMoving else {
                    return
                }
                let (hx, ahx) = resolveDividers()
                hiddenDividerX = hx
                alwaysHiddenDividerX = ahx
                let (grouped, midY) = buildSections(hiddenX: hx, alwaysHiddenX: ahx, axFallback: axFallback)
                if !grouped.isEmpty {
                    sections = grouped
                }
                if let midY {
                    anchorY = midY
                }
                if !sections.values.flatMap({ $0 }).contains(where: { $0.systemImage == nil && $0.appIcon == nil }) {
                    return
                }
            }
        }
    }

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
}

// MARK: - Row

private struct RowItem: Identifiable {
    /// Stable ID tied to the real item (not a random UUID per scan)
    /// so SwiftUI diffs smoothly and the item stays verifiable after drag-and-drop.
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String?
    let appIcon: NSImage?
    /// true for com.apple.* bundles: attaches the Apple logo badge as in the mock.
    let isSystem: Bool
    /// Frame in Quartz coordinates (top-left origin, same system as `CGEvent`),
    /// used as the start point for a Command-drag.
    let quartzFrame: CGRect?
    /// Process that owns the item, used to confirm it is really on screen.
    let pid: pid_t?
}

private struct SectionMeta {
    typealias Kind = MenuBarItemAXDiscovery.SectionKind

    let kind: Kind
    let title: String
    let icon: String
    let subtitle: String
    let emptyHint: String

    static let all = [
        SectionMeta(kind: .visible, title: "Visible", icon: "eye", subtitle: "Always in the menu bar", emptyHint: "No visible icons"),
        SectionMeta(kind: .hidden, title: "Hidden", icon: "eye.slash", subtitle: "A hover or click away — or ⌘-drag icons left of the chevron", emptyHint: "No hidden icons — drop icons here to hide them"),
        SectionMeta(kind: .alwaysHidden, title: "Always Hidden", icon: "moon", subtitle: "Out of sight until you double-click or ⌥-click the chevron", emptyHint: "No always-hidden icons — drop icons here to hide them"),
    ]
}

// MARK: - FlowLayout

/// Lay out subviews into multiple rows, wrapping when out of space.
/// Right-align each row to match the real menu bar (icons packed against the right edge).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: proposal, subviews: subviews) {
            for (position, index) in row.indices.enumerated() {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + row.x[position] + row.trailingOffset, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
            }
        }
    }

    private struct Row {
        var x = [CGFloat]()
        var indices = [Int]()
        var y: CGFloat = 0
        var height: CGFloat = 0
        /// Offset that packs the row against the right edge (= the remaining space).
        var trailingOffset: CGFloat = 0
        var width: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [Row]()
        var current = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        func finishRow() {
            // Push incomplete rows fully right to match the menu bar.
            if maxWidth.isFinite {
                current.trailingOffset = max(0, maxWidth - current.width)
            }
            rows.append(current)
            y += current.height + spacing
            current = Row()
            x = 0
        }
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > maxWidth {
                finishRow()
            }
            current.x.append(x)
            current.indices.append(index)
            current.height = max(current.height, size.height)
            current.y = y
            x += size.width + spacing
            current.width = x - spacing
        }
        if !current.indices.isEmpty {
            finishRow()
        }
        return rows
    }
}

// MARK: - Subtitle

private extension MenuBarItem {
    var subtitle: String {
        if let bundleID = owningApplication?.bundleIdentifier {
            bundleID
        } else if let ownerName {
            ownerName
        } else {
            title ?? ""
        }
    }
}

private extension MenuBarItemAXDiscovery.AXMenuBarItem {
    var subtitle: String? {
        if let identifier, identifier != displayName {
            identifier
        } else {
            bundleID
        }
    }
}
