//
//  DisplayInfo.swift
//  Ice
//

import Cocoa
import Combine

/// Information for a display.
struct DisplayInfo {
    /// An error that can be thrown during display operations.
    enum DisplayError: Error {
        case cannotComplete
        case failure
        case illegalArgument
        case invalidConnection
        case invalidContext
        case invalidOperation
        case invalidDisplayID
        case noneAvailable
        case notImplemented
        case rangeCheck
        case typeCheck
        case unknown
    }

    /// The display identifier associated with the display.
    let displayID: CGDirectDisplayID

    /// The bounds of the display.
    ///
    /// The bounds are expressed in the global display coordinate space,
    /// relative to the upper left corner of the main display.
    let bounds: CGRect

    /// The scale factor of the display.
    let scaleFactor: CGFloat

    /// The refresh rate of the display.
    let refreshRate: CGRefreshRate

    /// The color space of the display.
    let colorSpace: CGColorSpace

    /// The frame of the display.
    ///
    /// The frame is expressed in screen coordinates.
    var frame: CGRect {
        DisplayFrameHelper.shared.getFrame(for: self)
    }

    /// The `Cocoa` screen equivalent of the display.
    var nsScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// A Boolean value that indicates whether the display is the main display.
    var isMain: Bool {
        CGDisplayIsMain(displayID) != 0
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
        self.bounds = CGDisplayBounds(displayID)
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
    private static func getDisplayError(for cgError: CGError) -> DisplayError? {
        switch cgError {
        case .success: nil
        case .failure: .failure
        case .illegalArgument: .illegalArgument
        case .invalidConnection: .invalidConnection
        case .invalidContext: .invalidContext
        case .cannotComplete: .cannotComplete
        case .notImplemented: .notImplemented
        case .rangeCheck: .rangeCheck
        case .typeCheck: .typeCheck
        case .invalidOperation: .invalidOperation
        case .noneAvailable: .noneAvailable
        @unknown default: .unknown
        }
    }

    private static func getDisplayCount(activeDisplaysOnly: Bool) throws -> UInt32 {
        var displayCount: UInt32 = 0
        let result = if activeDisplaysOnly {
            CGGetActiveDisplayList(0, nil, &displayCount)
        } else {
            CGGetOnlineDisplayList(0, nil, &displayCount)
        }
        if let error = getDisplayError(for: result) {
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
        if let error = getDisplayError(for: result) {
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

// MARK: Helper
private class DisplayFrameHelper {
    static let shared = DisplayFrameHelper()

    private var cancellables = Set<AnyCancellable>()

    private var mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())

    private init() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
            }
            .store(in: &c)

        cancellables = c
    }

    func getFrame(for display: DisplayInfo) -> CGRect {
        let origin = CGPoint(
            x: display.bounds.origin.x,
            y: mainDisplayBounds.height - display.bounds.origin.y
        )
        return CGRect(origin: origin, size: display.bounds.size)
    }
}
