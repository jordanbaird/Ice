//
//  MacOS27DynamicItemState.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Runtime identities are deliberately not restored across Ice launches. An
/// unidentified AX item must be classified from the native bar again instead
/// of inheriting the assignment of an unrelated item with the same label.
enum MacOS27RuntimeItemIdentity {
    static let prefix = "Ice.RuntimeItem."

    static func isStoredIdentifier(_ identifier: String) -> Bool {
        identifier.contains(":\(prefix)")
    }
}

/// A small, bounded map of AX-object equality to identities. Labels and frames
/// are intentionally not inputs: both can change while the same item lives.
struct MacOS27RuntimeItemRegistry<Element> {
    private struct Entry {
        let element: Element
        let owner: String
        let identity: String
        var lastSeen: TimeInterval
    }

    private var entries = [Entry]()
    private let session = UUID().uuidString
    private var nextIdentity: UInt64 = 0
    private let capacity: Int

    var count: Int { entries.count }

    init(capacity: Int = 512) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    mutating func identity(
        for element: Element,
        owner: String,
        now: TimeInterval,
        equals: (Element, Element) -> Bool
    ) -> String {
        if let index = entries.firstIndex(where: { $0.owner == owner && equals($0.element, element) }) {
            entries[index].lastSeen = now
            return entries[index].identity
        }
        if entries.count >= capacity,
           let oldest = entries.indices.min(by: { entries[$0].lastSeen < entries[$1].lastSeen }) {
            entries.remove(at: oldest)
        }
        let identity = "\(MacOS27RuntimeItemIdentity.prefix)\(session).\(nextIdentity)"
        nextIdentity &+= 1
        entries.append(Entry(element: element, owner: owner, identity: identity, lastSeen: now))
        return identity
    }

    mutating func removeUnavailableOwners(_ owners: Set<String>) {
        entries.removeAll { !owners.contains($0.owner) }
    }
}

enum MacOS27ItemSnapshotGeometry {
    /// An off-bar child is not actionable, but its published AX identity still
    /// proves existence. Missing-item confirmation must not filter it out.
    static func includes(
        frame: CGRect,
        menuBarFrames: [CGRect],
        maxItemHeight: CGFloat,
        includingOffscreenItems: Bool
    ) -> Bool {
        includingOffscreenItems || (
            frame.width > 0 && frame.height > 0 && frame.height <= maxItemHeight &&
            menuBarFrames.contains { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        )
    }
}

/// Missing expanded snapshots receive a short grace period. Expiry merely
/// requests a successful owner reread; it is not proof of item withdrawal.
struct MacOS27MissingItemGrace {
    private var firstMissingAt = [String: TimeInterval]()

    mutating func saw(_ identifier: String) {
        firstMissingAt.removeValue(forKey: identifier)
    }

    mutating func needsVerification(_ identifier: String, canObserve: Bool, now: TimeInterval) -> Bool {
        guard canObserve else {
            saw(identifier)
            return false
        }
        guard let first = firstMissingAt[identifier] else {
            firstMissingAt[identifier] = now
            return false
        }
        return now - first >= 2
    }
}

/// Layout's refresh scope belongs to the editor session, not to its current
/// tiles. A living host with zero items must remain eligible to republish one.
struct MacOS27LayoutOwnerRegistry<Namespace: Hashable> {
    struct Owner: Hashable {
        let pid: Int32
        let namespace: Namespace
        let launchTime: TimeInterval?
    }

    private var isActive = false
    private var owners = Set<Owner>()
    private var namespaces = Set<Namespace>()
    private var previousRunningOwners = Set<Owner>()

    mutating func begin(knownOwners: Set<Owner>, runningOwners: Set<Owner>) {
        guard !isActive else { return }
        isActive = true
        previousRunningOwners = runningOwners
        observe(knownOwners.intersection(runningOwners))
    }

    mutating func end() {
        isActive = false
        owners.removeAll()
        namespaces.removeAll()
        previousRunningOwners.removeAll()
    }

    mutating func observe(_ publishedOwners: Set<Owner>) {
        guard isActive else { return }
        owners.formUnion(publishedOwners)
        namespaces.formUnion(publishedOwners.map(\.namespace))
    }

    mutating func runningApplicationsChanged(_ runningOwners: Set<Owner>) {
        guard isActive else { return }
        let launched = runningOwners.subtracting(previousRunningOwners)
        previousRunningOwners = runningOwners
        owners.formIntersection(runningOwners)
        observe(launched)
    }

    func targets(runningOwners: Set<Owner>) -> (sourcePIDs: Set<Int32>, namespaces: Set<Namespace>) {
        guard isActive else { return ([], []) }
        // Verify the process lifetime, not just the recycled numeric PID.
        // Namespaces also let the provider resolve an observed owner's restart.
        return (Set(owners.intersection(runningOwners).map(\.pid)), namespaces)
    }
}
