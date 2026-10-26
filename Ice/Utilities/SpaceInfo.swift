//
//  SpaceInfo.swift
//  Ice
//

import CoreGraphics

/// Information for a desktop space.
struct SpaceInfo: Hashable {
    /// The space's identifier.
    let spaceID: CGSSpaceID

    /// A Boolean value that indicates whether the space is fullscreen.
    let isFullscreen: Bool

    /// Creates a space with the given identifier.
    ///
    /// - Parameter spaceID: An identifier for a space.
    init(spaceID: CGSSpaceID) {
        self.spaceID = spaceID
        self.isFullscreen = Bridging.isSpaceFullscreen(spaceID)
    }

    /// Returns the active space.
    static func activeSpace() -> SpaceInfo {
        SpaceInfo(spaceID: Bridging.getActiveSpaceID())
    }

    /// Returns the current space on the given display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func currentSpace(for displayID: CGDirectDisplayID) -> SpaceInfo? {
        guard let spaceID = Bridging.getCurrentSpaceID(for: displayID) else {
            return nil
        }
        return SpaceInfo(spaceID: spaceID)
    }
}
