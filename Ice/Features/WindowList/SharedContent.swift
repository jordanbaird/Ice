//
//  SharedContent.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

class SharedContent: ObservableObject {
    let maxInterval: TimeInterval
    let queue: DispatchQueue

    private var timer: QueuedTimer?

    @Published private(set) var windows = [SCWindow]()
    @Published private(set) var displays = [SCDisplay]()
    @Published private(set) var applications = [SCRunningApplication]()

    init(maxInterval: TimeInterval, queue: DispatchQueue) {
        self.maxInterval = maxInterval
        self.queue = queue
    }

    func activate() {
        deactivate()
        let newTimer = QueuedTimer(interval: maxInterval, queue: queue) { [weak self] _ in
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
                    Logger.sharedContent.error("Error retrieving shareable content: \(error.localizedDescription)")
                }
            }
        }
        newTimer.start(fireImmediately: true)
        timer = newTimer
    }

    func deactivate() {
        timer?.stop()
        timer = nil
    }
}

// MARK: - Logger
extension Logger {
    static let sharedContent = Logger.mainSubsystem(category: "SharedContent")
}
