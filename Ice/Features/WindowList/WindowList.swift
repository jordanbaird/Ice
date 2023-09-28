//
//  WindowList.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit

class WindowList: ObservableObject {
    static let shared = WindowList(maxInterval: 2)

    let maxInterval: TimeInterval

    private var timer: QueuedTimer?

    @Published private(set) var windows = [SCWindow]()

    init(maxInterval: TimeInterval) {
        self.maxInterval = maxInterval
        self.timer = QueuedTimer(interval: maxInterval, queue: .global(qos: .utility)) { [weak self] _ in
            SCShareableContent.getWithCompletionHandler { [weak self] content, error in
                guard let self else {
                    return
                }
                if let content {
                    windows = content.windows
                }
                if let error {
                    Logger.windowList.error("Error retrieving window list: \(error.localizedDescription)")
                }
            }
        }
    }

    func activate() {
        timer?.start(fireImmediately: true)
    }

    func deactivate() {
        timer?.stop()
    }
}

// MARK: - Logger
extension Logger {
    static let windowList = Logger.mainSubsystem(category: "WindowList")
}
