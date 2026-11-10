//
//  RememberedItemStore27.swift
//  Ice
//

import Cocoa
import OSLog

/// What Ice knows of the items of applications it cannot see.
///
/// A concealed application publishes no `AXExtrasMenuBar` at all on macOS 27, so the only
/// account of its items is what Ice saw while they were on the bar — and, across a launch,
/// what it wrote down last time. See ``RememberedItem27``.
@available(macOS 27.0, *)
@MainActor
final class RememberedItemStore27 {
    private static let logger = Logger(category: "RememberedItemStore27")

    private(set) var itemsByBundleID = [String: [MenuBarItem]]()

    /// What was last written, so the bar's constant small movements do not write on every read.
    private var savedSignature: String?

    /// Reads back what was remembered, for the applications that are running now.
    ///
    /// An application that has gone is dropped, like one that stops while Ice runs, so a
    /// restarted application is never remembered by the identifiers of the process it replaced.
    func load() {
        guard let stored = Defaults.dictionary(forKey: .macOS27RememberedItems) else {
            return
        }
        var pids = [String: pid_t]()
        for application in NSWorkspace.shared.runningApplications {
            guard let bundleID = application.bundleIdentifier else {
                continue
            }
            pids[bundleID] = application.processIdentifier
        }
        let decoded = RememberedItems27.decode(anyStored: stored)
        if decoded.count < stored.count {
            Self.logger.notice(
                "Dropped \(stored.count - decoded.count, privacy: .public) of \(stored.count, privacy: .public) remembered applications: their records could not be read back"
            )
        }
        var loaded = [String: [MenuBarItem]]()
        for (bundleID, records) in decoded {
            guard let pid = pids[bundleID] else {
                continue
            }
            loaded[bundleID] = records.map { record in
                MenuBarItem(
                    tag: MenuBarItemTag(namespace: .string(bundleID), title: record.tag),
                    syntheticWindowID: record.windowID,
                    ownerPID: pid,
                    bounds: record.bounds,
                    title: record.title,
                    isOnScreen: false
                )
            }
        }
        itemsByBundleID = loaded
        Self.logger.notice("Remembered \(loaded.count, privacy: .public) applications' items from the last run")
    }

    /// Takes in what a read of the bar reported, and writes the set down if it changed.
    func remember(_ items: [MenuBarItem]) {
        var reported = [String: [MenuBarItem]]()
        for item in items where !item.isControlItem && !item.isSystemClone && item.canBeHidden {
            guard let bundleID = item.sourceApplication?.bundleIdentifier else {
                continue
            }
            reported[bundleID, default: []].append(item)
        }
        itemsByBundleID.merge(reported) { _, new in new }
        itemsByBundleID = itemsByBundleID.filter { _, items in
            items.allSatisfy { NSRunningApplication(processIdentifier: $0.ownerPID) != nil }
        }
        save()
    }

    /// Whether every one of the given applications has items Ice knows of.
    func knowsEveryItem(of bundleIDs: some Collection<String>) -> Bool {
        bundleIDs.allSatisfy { itemsByBundleID[$0] != nil }
    }

    /// The remembered items of the given concealed applications that a read has no account of.
    func items(ofConcealed bundleIDs: Set<String>, missingFrom reported: [MenuBarItem]) -> [MenuBarItem] {
        let seen = Set(reported.compactMap { $0.sourceApplication?.bundleIdentifier })
        return itemsByBundleID
            .filter { bundleID, _ in bundleIDs.contains(bundleID) && !seen.contains(bundleID) }
            .flatMap(\.value)
    }

    private func save() {
        let records = itemsByBundleID.mapValues { items in
            items.map { item in
                RememberedItem27(
                    tag: item.tag.title,
                    windowID: item.windowID,
                    bounds: item.bounds,
                    title: item.title
                )
            }
        }
        let signature = RememberedItems27.signature(of: records)
        guard signature != savedSignature else {
            return
        }
        savedSignature = signature
        Defaults.set(RememberedItems27.encode(records), forKey: .macOS27RememberedItems)
    }
}
