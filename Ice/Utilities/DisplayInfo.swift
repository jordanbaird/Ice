//
//  DisplayInfo.swift
//  Ice
//

import Cocoa

/// Information for a display.
struct DisplayInfo {
    /// The display identifier associated with the display.
    let displayID: CGDirectDisplayID

    /// The frame of the display, in the global display coordinate space.
    let frame: CGRect

    /// The scale factor of the display.
    let scaleFactor: CGFloat

    /// The refresh rate of the display.
    let refreshRate: CGRefreshRate

    /// The color space of the display.
    let colorSpace: CGColorSpace

    /// Creates a display with the given display identifier.
    init?(displayID: CGDirectDisplayID) {
        guard
            displayID != kCGNullDirectDisplay,
            let mode = CGDisplayCopyDisplayMode(displayID)
        else {
            return nil
        }
        self.displayID = displayID
        self.frame = CGDisplayBounds(displayID)
        self.scaleFactor = CGFloat(mode.pixelWidth) / CGFloat(mode.width)
        self.refreshRate = mode.refreshRate
        self.colorSpace = CGDisplayCopyColorSpace(displayID)
    }

    /// Creates a display from the given `Cocoa` screen.
    init?(nsScreen: NSScreen) {
        self.init(displayID: nsScreen.displayID)
    }

    /// Returns the `Cocoa` screen for the display.
    func getNSScreen() -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}

extension DisplayInfo {
    /// Returns the main display.
    static var main: DisplayInfo? {
        DisplayInfo(displayID: CGMainDisplayID())
    }
}

extension DisplayInfo {
    enum DisplayListError: Error {
        case cannotComplete
        case failure
        case illegalArgument
        case invalidConnection
        case invalidContext
        case invalidOperation
        case noneAvailable
        case notImplemented
        case rangeCheck
        case typeCheck
        case unknown

        init?(cgError: CGError) {
            switch cgError {
            case .success:
                return nil
            case .failure:
                self = .failure
            case .illegalArgument:
                self = .illegalArgument
            case .invalidConnection:
                self = .invalidConnection
            case .invalidContext:
                self = .invalidContext
            case .cannotComplete:
                self = .cannotComplete
            case .notImplemented:
                self = .notImplemented
            case .rangeCheck:
                self = .rangeCheck
            case .typeCheck:
                self = .typeCheck
            case .invalidOperation:
                self = .invalidOperation
            case .noneAvailable:
                self = .noneAvailable
            @unknown default:
                self = .unknown
            }
        }
    }

    /// Returns the current number of displays.
    ///
    /// - Parameter activeDisplaysOnly: A Boolean value that indicates whether
    ///   to return only the number of active displays.
    static func getDisplayCount(activeDisplaysOnly: Bool) -> Int {
        var displayCount: UInt32 = 0
        if activeDisplaysOnly {
            CGGetActiveDisplayList(0, nil, &displayCount)
        } else {
            CGGetOnlineDisplayList(0, nil, &displayCount)
        }
        return Int(displayCount)
    }

    /// Returns the current displays.
    ///
    /// - Parameter activeDisplaysOnly: A Boolean value that indicates whether
    ///   to return only the active displays.
    static func current(activeDisplaysOnly: Bool) async throws -> [DisplayInfo] {
        let task = Task {
            let displayCount = getDisplayCount(activeDisplaysOnly: activeDisplaysOnly)
            var displayIDs = Array(repeating: kCGNullDirectDisplay, count: displayCount)
            let result = if activeDisplaysOnly {
                CGGetActiveDisplayList(UInt32(displayCount), &displayIDs, nil)
            } else {
                CGGetOnlineDisplayList(UInt32(displayCount), &displayIDs, nil)
            }
            if let error = DisplayListError(cgError: result) {
                throw error
            }
            return displayIDs.compactMap { displayID in
                DisplayInfo(displayID: displayID)
            }
        }
        return try await task.value
    }
}
