//
//  ScreenCaptureManager.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

class ScreenCaptureManager: ObservableObject {
    /// Options that affect the image or images returned from a capture.
    struct CaptureOptions: OptionSet {
        let rawValue: Int

        /// If the `screenBounds` parameter of the capture is `nil`,
        /// captures only the window area and ignores the area occupied
        /// by any framing effects.
        static let ignoreFraming = CaptureOptions(rawValue: 1 << 0)

        /// Captures only the shadow effects of the provided windows.
        static let onlyShadows = CaptureOptions(rawValue: 1 << 1)

        /// Fills the partially or fully transparent areas of the capture
        /// with a solid white backing color, resulting in an image that
        /// is fully opaque.
        static let shouldBeOpaque = CaptureOptions(rawValue: 1 << 2)

        /// The cursor is shown in the capture.
        static let showsCursor = CaptureOptions(rawValue: 1 << 3)

        /// The output is scaled to fit the configured width and height.
        static let scalesToFit = CaptureOptions(rawValue: 1 << 4)
    }

    /// An error that can occur during a capture.
    enum CaptureError: Error {
        /// The screen capture manager does not contain a window that
        /// matches the provided window.
        case noMatchingWindow

        /// The screen capture manager does not contain a display that
        /// matches the provided display.
        case noMatchingDisplay

        /// The provided window is not on screen.
        case windowOffScreen

        /// The source rectangle of the capture is outside the bounds
        /// of the provided window.
        case sourceRectOutOfBounds

        /// The capture operation timed out.
        case timeout
    }

    /// The shared screen capture manager.
    static let shared = ScreenCaptureManager(interval: 3, runLoop: .main, mode: .default)

    private var updateTimer: AnyCancellable?

    /// The apps that are available to capture.
    @Published private(set) var applications = [SCRunningApplication]()

    /// The displays that are available to capture.
    @Published private(set) var displays = [SCDisplay]()

    /// The windows that are available to capture.
    @Published private(set) var windows = [SCWindow]()

    /// A Boolean value that indicates whether the manager is
    /// continuously updating its content.
    var isContinuouslyUpdating: Bool {
        updateTimer != nil
    }

    /// A Boolean value that indicates whether the app has
    /// screen capture permissions.
    var hasScreenCapturePermissions: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The time interval at which to continuously update the
    /// manager's content.
    var interval: TimeInterval {
        didSet {
            if isContinuouslyUpdating {
                // reinitialize the timer using the new interval
                startContinuouslyUpdating()
            }
        }
    }

    /// The run loop on which to continuously update the
    /// manager's content.
    var runLoop: RunLoop {
        didSet {
            if isContinuouslyUpdating {
                // reinitialize the timer using the new run loop
                startContinuouslyUpdating()
            }
        }
    }

    /// The run loop mode in which to continuously update the
    /// manager's content.
    var mode: RunLoop.Mode {
        didSet {
            if isContinuouslyUpdating {
                // reinitialize the timer using the new mode
                startContinuouslyUpdating()
            }
        }
    }

    /// Creates a screen capture manager with the given interval,
    /// run loop, and run loop mode.
    init(interval: TimeInterval, runLoop: RunLoop, mode: RunLoop.Mode) {
        self.interval = interval
        self.runLoop = runLoop
        self.mode = mode
        startContinuouslyUpdating()
    }

    func update() {
        guard hasScreenCapturePermissions else {
            Logger.screenCaptureManager.notice("Missing screen capture permissions")
            return
        }
        SCShareableContent.getWithCompletionHandler { content, error in
            if let error {
                Logger.screenCaptureManager.error("Error updating shareable content: \(error)")
            }
            self.applications = content?.applications ?? []
            self.displays = content?.displays ?? []
            self.windows = content?.windows ?? []
        }
    }

    /// Starts continuously updating the manager's content.
    ///
    /// The content will update according to the value set by
    /// the manager's ``interval`` property.
    func startContinuouslyUpdating() {
        update()
        updateTimer = Timer.publish(every: interval, on: runLoop, in: mode)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                update()
            }
    }

    /// Stops the manager's content from continuously updating.
    ///
    /// The manager will retain the current content, but it will
    /// not stay up to date.
    func stopContinuouslyUpdating() {
        updateTimer?.cancel()
        updateTimer = nil
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - timeout: Amount of time to wait before throwing a cancellation error.
    ///   - window: The window to capture. The window must be on screen.
    ///   - display: The display of the capture.
    ///   - captureRect: The rectangle to capture, relative to the coordinate
    ///     space of the window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    func captureImage(
        withTimeout timeout: Duration,
        window: SCWindow,
        display: SCDisplay,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        guard let window = windows.first(where: { $0.windowID == window.windowID }) else {
            throw CaptureError.noMatchingWindow
        }
        guard let display = displays.first(where: { $0.displayID == display.displayID }) else {
            throw CaptureError.noMatchingDisplay
        }
        guard window.isOnScreen else {
            throw CaptureError.windowOffScreen
        }

        let captureRect = captureRect ?? .null
        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let sourceRect = if captureRect.isNull {
            windowBounds
        } else {
            captureRect
        }

        guard windowBounds.contains(sourceRect) else {
            throw CaptureError.sourceRectOutOfBounds
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()

        let displayID = display.displayID
        let scale = getDisplayScaleFactor(displayID)

        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width * scale)
        configuration.height = Int(sourceRect.height * scale)
        configuration.captureResolution = resolution
        configuration.colorSpaceName = CGColorSpace.displayP3
        configuration.ignoreShadowsSingleWindow = options.contains(.ignoreFraming)
        configuration.capturesShadowsOnly = options.contains(.onlyShadows)
        configuration.shouldBeOpaque = options.contains(.shouldBeOpaque)
        configuration.showsCursor = options.contains(.showsCursor)
        configuration.scalesToFit = options.contains(.scalesToFit)

        let captureTask = Task {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            )
            try Task.checkCancellation()
            return image
        }

        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            captureTask.cancel()
        }

        do {
            let result = try await captureTask.value
            timeoutTask.cancel()
            return result
        } catch is CancellationError {
            throw CaptureError.timeout
        }
    }

    private func getDisplayScaleFactor(_ displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 1
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

// MARK: - Logger
private extension Logger {
    static let screenCaptureManager = Logger(category: "ScreenCaptureManager")
}
