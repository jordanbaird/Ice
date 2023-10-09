//
//  SharedContent.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

/// An `ObservableObject` that routinely publishes the displays,
/// apps, and windows that are available for capture.
class SharedContent: ObservableObject {
    /// The interval at which the content is published.
    let interval: TimeInterval

    /// The dispatch queue to use to determine the timing with
    /// which to publish the content.
    let queue: DispatchQueue

    /// Timer that manages the publishing of the shared content
    /// using the instance's ``interval`` and ``queue``.
    private var timer: QueuedTimer?

    /// The most recently published windows.
    @Published private(set) var windows = [SCWindow]()

    /// The most recently published displays.
    @Published private(set) var displays = [SCDisplay]()

    /// The most recently published applications.
    @Published private(set) var applications = [SCRunningApplication]()

    /// Creates an instance that publishes its content using the
    /// given interval and dispatch queue.
    ///
    /// - Parameters:
    ///   - interval: The interval at which the content is published.
    ///   - queue: The dispatch queue to use to determine the timing
    ///     with which to publish the content.
    init(interval: TimeInterval, queue: DispatchQueue) {
        self.interval = interval
        self.queue = queue
    }

    /// Starts publishing the content using the instance's ``interval``
    /// and ``queue`` properties.
    ///
    /// The first changes are published immediately when this function
    /// is called. If the instance is already active, it is deactivated
    /// and immediately reactivated.
    func activate() {
        deactivate()
        let newTimer = QueuedTimer(interval: interval, queue: queue) { [weak self] _ in
            SCShareableContent.getWithCompletionHandler { [weak self] content, error in
                guard let self else {
                    return
                }
                if let content {
                    windows = content.windows
                    displays = content.displays
                    applications = content.applications
                }
                if let error {
                    Logger.sharedContent.error("Error retrieving shared content: \(error.localizedDescription)")
                }
            }
        }
        newTimer.start(fireImmediately: true)
        timer = newTimer
    }

    /// Stops publishing the content.
    func deactivate() {
        timer?.stop()
        timer = nil
    }
}

// MARK: - Logger
private extension Logger {
    static let sharedContent = Logger.mainSubsystem(category: "SharedContent")
}
