//
//  SyntheticWindowID27.swift
//  Ice
//

import Foundation

/// Identifiers for menu bar items that have no WindowServer window on macOS 27.
///
/// Ice's item model is keyed by window identifier. Real identifiers are small
/// counters, so synthetic ones set the top bit to stay out of their way.
enum SyntheticWindowID27 {
    static let flag: UInt32 = 0x8000_0000

    /// A stable identifier for an item, derived from its owner, identifier and position among the owner's items.
    static func make(bundleID: String, identifier: String, index: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in "\(bundleID)\u{1F}\(identifier)\u{1F}\(index)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return flag | (hash & ~flag)
    }

    static func isSynthetic(_ windowID: UInt32) -> Bool {
        windowID & flag != 0
    }
}
