//
//  AccessibilityScanSchedule27.swift
//  Ice
//

import Foundation

/// Decides how long to wait for each process when Ice reads menu bar items
/// through Accessibility on macOS 27.
///
/// Ice asks every running process for its items. Some processes never answer,
/// such as WebKit's content processes, and each costs the whole timeout on every
/// read: measured 17 of them and 8.5 s of a 10 s read. A process that times out
/// is skipped for a while, then asked again with a short timeout. A process that
/// has shown items is never skipped: a busy MenuBarAgent or item owner would
/// otherwise lose its items, and the clock its click, for a minute.
struct AccessibilityScanSchedule27 {
    static let normalTimeout: Float = 0.5
    static let retryTimeout: Float = 0.1

    private static let firstPause: TimeInterval = 60
    private static let longestPause: TimeInterval = 600

    private var pauses = [pid_t: (failures: Int, retryAt: TimeInterval)]()
    private var itemOwners = Set<pid_t>()

    /// The timeout to ask the process with, or `nil` to skip it for now.
    func timeout(for pid: pid_t, now: TimeInterval) -> Float? {
        guard let pause = pauses[pid] else {
            return Self.normalTimeout
        }
        return now >= pause.retryAt ? Self.retryTimeout : nil
    }

    /// Remembers a process that published menu bar items.
    mutating func recordItems(pid: pid_t) {
        itemOwners.insert(pid)
        pauses[pid] = nil
    }

    mutating func record(pid: pid_t, timedOut: Bool, now: TimeInterval) {
        guard timedOut, !itemOwners.contains(pid) else {
            pauses[pid] = nil
            return
        }
        let failures = (pauses[pid]?.failures ?? 0) + 1
        let pause = min(Self.firstPause * pow(2, Double(failures - 1)), Self.longestPause)
        pauses[pid] = (failures, now + pause)
    }

    /// Forgets processes that are no longer running.
    mutating func retain(running pids: Set<pid_t>) {
        pauses = pauses.filter { pids.contains($0.key) }
        itemOwners.formIntersection(pids)
    }
}
