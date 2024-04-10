//
//  Bundle+displayName.swift
//  Ice
//

import Foundation

extension Bundle {
    /// The bundle's display name.
    ///
    /// This accessor looks for an associated value for either `CFBundleDisplayName`
    /// or `CFBundleName` in the bundle's information property list (`Info.plist`)
    /// file. If a string value cannot be found for one of these keys, this accessor
    /// returns `nil`.
    var displayName: String? {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
