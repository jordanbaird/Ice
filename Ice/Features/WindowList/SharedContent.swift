//
//  SharedContent.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

/// An object that routinely publishes the displays, apps, and
/// windows that are available for capture.
class SharedContent: ObservableObject {
    /// The most recently published windows.
    @Published private(set) var windows = [SCWindow]()

    /// The most recently published displays.
    @Published private(set) var displays = [SCDisplay]()

    /// The most recently published applications.
    @Published private(set) var applications = [SCRunningApplication]()

    /// The time interval at which the content is published.
    ///
    /// - Note: Setting this value immediately publishes the content.
    ///   The content will then be published using the new interval.
    var interval: TimeInterval {
        didSet {
            let isActive = isActive
            deactivate()
            if isActive {
                activate()
            }
        }
    }

    /// A Boolean value that indicates whether the content is
    /// actively being published.
    var isActive: Bool {
        timer != nil
    }

    /// The dispatch queue used to determine the timing with
    /// which to publish the content.
    private let queue = DispatchQueue.global(qos: .utility)

    /// Timer that manages the publishing of the shared content
    /// using the instance's ``interval`` and ``queue``.
    private var timer: QueuedTimer?

    /// Creates an instance that publishes its content using the
    /// given time interval.
    ///
    /// - Parameter interval: The time interval at which the content
    ///   is published.
    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    /// Starts publishing the content using the instance's ``interval``.
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
                    Logger.sharedContent.error("Error retrieving shared content: \(error)")
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
