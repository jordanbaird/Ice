//
//  Comparable+clamped.swift
//  Ice
//

extension Comparable {
    /// Returns a copy of this value that has been clamped
    /// within the bounds of the given limiting range.
    ///
    /// - Parameter limits: A closed range within which to
    ///   clamp this value.
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
