//
//  MenuBarItemSourceResolver.swift
//  Ice
//

import ApplicationServices
import Cocoa
import os

/// Finds the app that created each menu bar item window on macOS 26.
///
/// On macOS 26 the window server reports Control Center as the owner of
/// every menu bar item window. Ice used the owner to name items and to
/// find its own section dividers, so on macOS 26 it could not find the
/// dividers, and every icon showed Control Center's name and app icon.
///
/// This matches item windows to the apps' Accessibility items by position,
/// the same way IceMelt and Thaw handle macOS 26. Ice's own windows are
/// matched against its own status bar windows instead, since an
/// Accessibility request into Ice's own process from the main thread would
/// stall.
///
/// macOS 14–15 report the right owner and macOS 27 has no per-item windows,
/// so the resolver does nothing there.
enum MenuBarItemSourceResolver {
    /// Whether this macOS version reports Control Center as the owner of
    /// every menu bar item window.
    static let isNeeded: Bool = {
        if #available(macOS 27, *) {
            return false
        }
        if #available(macOS 26, *) {
            return true
        }
        return false
    }()

    /// Resolved source process identifiers and retry bookkeeping.
    private struct State {
        /// Source process identifiers, keyed by item window.
        var pids = [CGWindowID: pid_t]()

        /// How many resolve passes in a row failed to place each window.
        var misses = [CGWindowID: Int]()
    }

    /// After this many failed passes, a window stops asking for retries.
    /// Some items have no Accessibility element at all; without a limit
    /// they would force a full rescan every few seconds forever.
    private static let maxMisses = 3

    private static let state = OSAllocatedUnfairLock(initialState: State())

    private static let logger = Logger(category: "SourceResolver")

    /// Returns the resolved source process identifier for the given window,
    /// or `nil` if it is unknown or the resolver isn't needed.
    static func sourcePID(for windowID: CGWindowID) -> pid_t? {
        guard isNeeded else {
            return nil
        }
        return state.withLock { $0.pids[windowID] }
    }

    /// Resolves the source process for each of the given menu bar item windows.
    ///
    /// - Parameter windowIDs: The menu bar item windows to resolve.
    /// - Returns: `true` when nothing is left worth retrying: every window has
    ///   a source, or the unresolved ones have already been retried enough.
    @MainActor
    static func resolve(windowIDs: [CGWindowID]) async -> Bool {
        guard isNeeded else {
            return true
        }

        let windows = windowIDs.compactMap { WindowInfo(windowID: $0) }
        var resolved = [CGWindowID: pid_t]()

        // Ice's own items first: by matching its own status bar windows, or
        // by title, since the window titles are Ice's own autosave names.
        // Done before the Accessibility pass so another app's item can't
        // claim one of Ice's windows.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownFrames = ownStatusItemFrames()
        let ownTitles = Set(ControlItem.Identifier.allCases.map(\.rawValue))
        for window in windows {
            let matchesFrame = ownFrames.contains { matchesOwnFrame(window.frame, $0) }
            let matchesTitle = window.title.map { ownTitles.contains($0) } ?? false
            if matchesFrame || matchesTitle {
                resolved[window.windowID] = ownPID
            }
        }

        // Then everything else, by matching Accessibility item frames.
        let remaining = windows.filter { resolved[$0.windowID] == nil }
        if !remaining.isEmpty, AXIsProcessTrusted() {
            let pids = candidateProcessIdentifiers()
            let items = await Task.detached(priority: .userInitiated) {
                MenuBarItemAXDiscovery.itemFrames(ofProcesses: pids)
            }.value
            resolved.merge(match(windows: remaining, items: items)) { current, _ in current }
        }

        let currentIDs = Set(windowIDs)
        let placed = resolved
        let isComplete = state.withLock { state in
            // Forget windows that no longer exist.
            state.pids = state.pids.filter { currentIDs.contains($0.key) }
            state.misses = state.misses.filter { currentIDs.contains($0.key) }

            var isComplete = true
            for windowID in windowIDs {
                if let pid = placed[windowID] {
                    state.pids[windowID] = pid
                    state.misses[windowID] = nil
                } else if state.pids[windowID] == nil {
                    // Not placed this time and never placed before.
                    let misses = state.misses[windowID, default: 0] + 1
                    state.misses[windowID] = misses
                    if misses < maxMisses {
                        isComplete = false
                    }
                }
                // A window placed before but not this time keeps its old
                // source: a single pass taken mid-move shouldn't erase it.
            }
            return isComplete
        }
        if !isComplete {
            logger.debug("Some menu bar item windows have no source yet; will retry")
        }
        return isComplete
    }

    /// Frames of Ice's own status bar windows, in CoreGraphics coordinates.
    @MainActor
    private static func ownStatusItemFrames() -> [CGRect] {
        guard let primaryScreen = NSScreen.screens.first else {
            return []
        }
        let primaryHeight = primaryScreen.frame.height
        return NSApp.windows.compactMap { window in
            guard window.className.hasSuffix("StatusBarWindow") else {
                return nil
            }
            let frame = window.frame
            // AppKit's origin is bottom-left of the primary screen;
            // CoreGraphics' is top-left.
            return CGRect(
                x: frame.minX,
                y: primaryHeight - frame.maxY,
                width: frame.width,
                height: frame.height
            )
        }
    }

    /// Whether an item window's frame is the same as one of Ice's own
    /// status bar window frames.
    private static func matchesOwnFrame(_ windowFrame: CGRect, _ ownFrame: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        return abs(windowFrame.minX - ownFrame.minX) <= tolerance &&
            abs(windowFrame.maxX - ownFrame.maxX) <= tolerance &&
            abs(windowFrame.midY - ownFrame.midY) <= windowFrame.height
    }

    /// Process identifiers of the apps that may own menu bar items.
    ///
    /// Leaves out Ice itself, and processes that can't have a menu bar item
    /// and may not answer Accessibility at all (XPC services, daemons).
    @MainActor
    private static func candidateProcessIdentifiers() -> [pid_t] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard
                app.processIdentifier != ownPID,
                app.isFinishedLaunching,
                !app.isTerminated,
                app.activationPolicy != .prohibited || app.bundleURL?.pathExtension == "app"
            else {
                return nil
            }
            return app.processIdentifier
        }
    }

    /// Pairs item windows with Accessibility items by horizontal position.
    ///
    /// A pair is allowed when the item's center lies inside the window's
    /// horizontal span. Allowed pairs are scored by center distance (width
    /// difference breaks ties) and claimed best-first, so each window and
    /// each item is used once. Only the horizontal axis is compared:
    /// Accessibility frames are centered in the bar, while item windows
    /// span its full height.
    private static func match(
        windows: [WindowInfo],
        items: [(pid: pid_t, frame: CGRect)]
    ) -> [CGWindowID: pid_t] {
        var pairs = [(score: CGFloat, windowIndex: Int, itemIndex: Int)]()
        for (windowIndex, window) in windows.enumerated() {
            let bounds = window.frame
            for (itemIndex, item) in items.enumerated() {
                let midX = item.frame.midX
                guard bounds.minX <= midX, midX <= bounds.maxX else {
                    continue
                }
                let score = abs(bounds.midX - midX) * 10 + abs(bounds.width - item.frame.width)
                pairs.append((score, windowIndex, itemIndex))
            }
        }

        var result = [CGWindowID: pid_t]()
        var usedWindows = Set<Int>()
        var usedItems = Set<Int>()
        for pair in pairs.sorted(by: { $0.score < $1.score }) {
            guard
                !usedWindows.contains(pair.windowIndex),
                !usedItems.contains(pair.itemIndex)
            else {
                continue
            }
            usedWindows.insert(pair.windowIndex)
            usedItems.insert(pair.itemIndex)
            result[windows[pair.windowIndex].windowID] = items[pair.itemIndex].pid
        }
        return result
    }
}
