//
//  RefreshSequencer.swift
//  Ice
//

/// Numbers asynchronous refreshes so that a slow, superseded refresh can't
/// publish over a newer one.
struct RefreshSequencer {
    private var latest: UInt64 = 0

    /// Starts a refresh; every earlier refresh stops being current.
    mutating func begin() -> UInt64 {
        latest += 1
        return latest
    }

    /// Supersedes every refresh in flight.
    mutating func invalidate() {
        latest += 1
    }

    func isCurrent(_ token: UInt64) -> Bool {
        token == latest
    }
}
