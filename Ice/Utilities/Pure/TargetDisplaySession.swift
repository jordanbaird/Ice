//
//  TargetDisplaySession.swift
//  Ice
//

/// The display a section targets during one show-to-hide cycle.
struct TargetDisplaySession {
    private(set) var pinnedDisplayID: UInt32?

    /// Starts a cycle on the display that `resolve` returns now.
    mutating func begin(resolve: () -> UInt32) -> UInt32 {
        let id = resolve()
        pinnedDisplayID = id
        return id
    }

    /// The display to use for the rehide checks.
    ///
    /// During a cycle this is the display pinned when the section was shown,
    /// NOT a fresh resolution: with the system call returning `nil` the
    /// resolver follows the pointer, so the target would chase the cursor
    /// across screens. Returns `nil` if the pinned display disconnected.
    func displayID(connected: Set<UInt32>, resolve: () -> UInt32) -> UInt32? {
        guard let pinnedDisplayID else {
            return resolve()
        }
        return connected.contains(pinnedDisplayID) ? pinnedDisplayID : nil
    }

    mutating func end() {
        pinnedDisplayID = nil
    }
}
