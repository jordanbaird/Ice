//
//  Bundle+copyrightString.swift
//  Ice
//

import Foundation

extension Bundle {
    /// The bundle's copyright string.
    ///
    /// This accessor looks for an associated value for the `NSHumanReadableCopyright`
    /// key in the bundle's information property list (`Info.plist`) file. If a string
    /// value cannot be found for this key, this accessor returns `nil`.
    var copyrightString: String? {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }
}
