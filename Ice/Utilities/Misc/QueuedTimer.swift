//
//  QueuedTimer.swift
//  Ice
//

import Foundation

/// A timer that is scheduled on a dispatch queue.
///
/// Unlike the `Timer` type from Foundation, this timer type does not
/// rely on a run loop to operate.
class QueuedTimer {
    /// The interval at which the timer repeats.
    let interval: TimeInterval

    /// The queue that the timer runs on.
    let queue: DispatchQueue?

    /// A handler to perform when the timer is fired.
    private let block: (QueuedTimer) -> Void

    /// The dispatch source timer at the root of this timer.
    private var sourceTimer: DispatchSourceTimer? {
        didSet {
            oldValue?.cancel()
        }
    }

    /// A Boolean value that indicates whether the timer is valid.
    var isValid: Bool {
        sourceTimer != nil
    }

    /// Creates a queued timer with the given interval, queue, and block.
    ///
    /// - Parameters:
    ///   - interval: The interval at which the timer repeats.
    ///   - queue: The queue that the timer runs on.
    ///   - block: A handler to perform when the timer is fired.
    init(
        interval: TimeInterval,
        queue: DispatchQueue? = nil,
        block: @escaping (QueuedTimer) -> Void
    ) {
        self.interval = interval
        self.queue = queue
        self.block = block
    }

    deinit {
        stop()
    }

    /// Creates and returns a dispatch source timer.
    private func makeSourceTimer(fireImmediately: Bool) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            if let self {
                block(self)
            }
        }
        let deadline = if fireImmediately {
            DispatchTime.now()
        } else {
            DispatchTime.now() + interval
        }
        timer.schedule(deadline: deadline, repeating: interval)
        return timer
    }

    /// Starts the timer.
    ///
    /// - Parameter fireImmediately: A Boolean value that indicates whether the
    ///   timer's handler should be performed immediately after it is scheduled.
    func start(fireImmediately: Bool = false) {
        let timer = makeSourceTimer(fireImmediately: fireImmediately)
        sourceTimer = timer
        timer.resume()
    }

    /// Immediately performs the timer's handler and reschedules the timer.
    func fire() {
        if isValid {
            start(fireImmediately: true)
        }
    }

    /// Stops the timer.
    func stop() {
        sourceTimer = nil
    }
}
