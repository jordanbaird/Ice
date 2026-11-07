//
//  BarPresentationTracker.swift
//  Ice
//

/// Tracks which display and section the Trincano Bar is being presented on.
struct BarPresentationTracker<Section: Hashable> {
    struct Presentation: Equatable {
        let token: UInt64
        let displayID: UInt32
        let section: Section
    }

    private(set) var presentation: Presentation?
    private var nextToken: UInt64 = 0

    mutating func begin(displayID: UInt32, section: Section) -> UInt64 {
        nextToken += 1
        presentation = Presentation(token: nextToken, displayID: displayID, section: section)
        return nextToken
    }

    /// Returns whether a presentation that was waiting (for the cache) may
    /// still be put on screen: it must be the current one and its display
    /// must still be connected.
    func canPublish(token: UInt64, connectedDisplayIDs: Set<UInt32>) -> Bool {
        guard let presentation, presentation.token == token else {
            return false
        }
        return connectedDisplayIDs.contains(presentation.displayID)
    }

    /// Call when the connected displays change. If the display the bar was
    /// being presented on is gone (visible or still preparing), the
    /// presentation is cancelled and the section that was really presented
    /// is returned so it can be closed. The identity comes from when the show
    /// began, never from the window's current `screen`.
    mutating func reconcile(connectedDisplayIDs: Set<UInt32>) -> Section? {
        guard let presentation, !connectedDisplayIDs.contains(presentation.displayID) else {
            return nil
        }
        self.presentation = nil
        return presentation.section
    }

    mutating func end() {
        presentation = nil
    }
}
