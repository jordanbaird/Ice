//
//  ScreenCaptureManager.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

/// A manager for screen capture operations.
class ScreenCaptureManager: ObservableObject {
    /// Options that define additional parameters for a capture.
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
        /// The app does not have screen capture permissions.
        case missingPermissions

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

    private var cancellables = Set<AnyCancellable>()

    private var updateTimer: AnyCancellable?

    private var screenIsLocked = false

    private var screenSaverIsActive = false

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
        configureCancellables()
        startContinuouslyUpdating()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = false
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = false
            }
            .store(in: &c)

        cancellables = c
    }

    /// Immediately updates the manager's content, performing the
    /// given completion handler when finished.
    func updateWithCompletionHandler(_ completionHandler: @escaping () -> Void) {
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
            completionHandler()
        }
    }

    /// Starts continuously updating the manager's content.
    ///
    /// The content will update according to the value set by
    /// the manager's ``interval`` property.
    func startContinuouslyUpdating() {
        updateWithCompletionHandler { }
        updateTimer = Timer.publish(every: interval, on: runLoop, in: mode)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateWithCompletionHandler { }
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

    /// Returns the wallpaper window for the given display.
    func wallpaperWindow(for display: DisplayInfo) -> SCWindow? {
        windows.first { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.isOnScreen &&
            window.title?.hasPrefix("Wallpaper-") == true &&
            display.frame.contains(window.frame)
        }
    }

    /// Returns the menu bar window for the given display.
    func menuBarWindow(for display: DisplayInfo) -> SCWindow? {
        windows.first { window in
            // menu bar window belongs to the WindowServer process
            // (identified by an empty string)
            window.owningApplication?.bundleIdentifier == "" &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            display.frame.contains(window.frame)
        }
    }

    /// Returns an image containing the area of the desktop wallpaper
    /// that is below the menu bar for the given display.
    func desktopWallpaperBelowMenuBar(for display: DisplayInfo) async throws -> CGImage? {
        guard
            !screenIsLocked,
            !screenSaverIsActive,
            let wallpaperWindow = wallpaperWindow(for: display),
            let menuBarWindow = menuBarWindow(for: display)
        else {
            return nil
        }
        return try await captureImage(
            withTimeout: .milliseconds(500),
            windowPredicate: { $0.windowID == wallpaperWindow.windowID },
            displayPredicate: { $0.displayID == display.displayID },
            captureRect: CGRect(origin: .zero, size: menuBarWindow.frame.size),
            options: .ignoreFraming
        )
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - timeout: The amount of time to wait before cancelling the task
    ///     and throwing a timeout error.
    ///   - window: The window to capture. The window must be on screen.
    ///   - display: The display to capture.
    ///   - captureRect: The rectangle to capture, relative to the coordinate
    ///     space of the window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    func captureImage(
        withTimeout timeout: Duration,
        windowPredicate: (SCWindow) throws -> Bool,
        displayPredicate: (SCDisplay) throws -> Bool,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        guard hasScreenCapturePermissions else {
            throw CaptureError.missingPermissions
        }
        guard let window = try windows.first(where: windowPredicate) else {
            throw CaptureError.noMatchingWindow
        }
        guard let display = try displays.first(where: displayPredicate) else {
            throw CaptureError.noMatchingDisplay
        }
        guard window.isOnScreen else {
            throw CaptureError.windowOffScreen
        }

        let sourceRect = try getSourceRect(captureRect: captureRect, window: window)

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

    private func getSourceRect(captureRect: CGRect?, window: SCWindow) throws -> CGRect {
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
        return sourceRect
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
