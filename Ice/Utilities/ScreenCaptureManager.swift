//
//  ScreenCaptureManager.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

class ScreenCaptureManager: ObservableObject {
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
}

// MARK: - Logger
private extension Logger {
    static let screenCaptureManager = Logger(category: "ScreenCaptureManager")
}
