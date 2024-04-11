//
//  DisplayInfo.swift
//  Ice
//

import Cocoa

/// Information for a display.
struct DisplayInfo {
    /// The display identifier associated with the display.
    let displayID: CGDirectDisplayID

    /// The frame of the display.
    ///
    /// The frame is specified in the global display coordinate space.
    let frame: CGRect

    /// The scale factor of the display.
    let scaleFactor: CGFloat

    /// The refresh rate of the display.
    let refreshRate: CGRefreshRate

    /// The color space of the display.
    let colorSpace: CGColorSpace

    /// The `Cocoa` screen equivalent of the display.
    var nsScreen: NSScreen? {
        NSScreen.screens.first { screen in
            screen.displayID == displayID
        }
    }

    /// Creates a display with the given display identifier.
    ///
    /// - Note: If the display identifier is equivalent to `kCGNullDirectDisplay`,
    ///   or is otherwise invalid, this initializer returns `nil`.
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

    /// Creates a display from the given `Cocoa` screen equivalent.
    init?(nsScreen: NSScreen) {
        self.init(displayID: nsScreen.displayID)
    }
}

extension DisplayInfo {
    /// The main display.
    static var main: DisplayInfo? {
        DisplayInfo(displayID: CGMainDisplayID())
    }
}

extension DisplayInfo {
    /// An error that can be thrown during display list operations.
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

    private static func getDisplayCount(activeDisplaysOnly: Bool) throws -> UInt32 {
        var displayCount: UInt32 = 0
        let result = if activeDisplaysOnly {
            CGGetActiveDisplayList(0, nil, &displayCount)
        } else {
            CGGetOnlineDisplayList(0, nil, &displayCount)
        }
        if let error = DisplayListError(cgError: result) {
            throw error
        }
        return displayCount
    }

    private static func getDisplayList(activeDisplaysOnly: Bool) throws -> [CGDirectDisplayID] {
        let displayCount = try getDisplayCount(activeDisplaysOnly: activeDisplaysOnly)
        var displayIDs = Array(repeating: kCGNullDirectDisplay, count: Int(displayCount))
        let result = if activeDisplaysOnly {
            CGGetActiveDisplayList(displayCount, &displayIDs, nil)
        } else {
            CGGetOnlineDisplayList(displayCount, &displayIDs, nil)
        }
        if let error = DisplayListError(cgError: result) {
            throw error
        }
        return displayIDs
    }

    /// Returns the current displays.
    ///
    /// - Parameter activeDisplaysOnly: A Boolean value that indicates whether
    ///   to return only the active displays.
    static func getCurrent(activeDisplaysOnly: Bool) throws -> [DisplayInfo] {
        let displayIDs = try getDisplayList(activeDisplaysOnly: activeDisplaysOnly)
        return displayIDs.compactMap { displayID in
            DisplayInfo(displayID: displayID)
        }
    }

    /// Asynchronously returns the current displays.
    ///
    /// - Parameter activeDisplaysOnly: A Boolean value that indicates whether
    ///   to return only the active displays.
    static func current(activeDisplaysOnly: Bool) async throws -> [DisplayInfo] {
        let task = Task.detached {
            let displayIDs = try getDisplayList(activeDisplaysOnly: activeDisplaysOnly)

            try Task.checkCancellation()
            await Task.yield()

            var displays = [DisplayInfo]()
            for displayID in displayIDs {
                try Task.checkCancellation()
                await Task.yield()
                if let display = DisplayInfo(displayID: displayID) {
                    displays.append(display)
                }
            }

            return displays
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
