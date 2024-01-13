//
//  Bundle+versionString.swift
//  Ice
//

import Foundation

extension Bundle {
    /// The bundle's version string.
    ///
    /// This accessor looks for an associated value for either `CFBundleShortVersionString`
    /// or `CFBundleVersion` in the bundle's information property list (`Info.plist`)
    /// file. If a string value cannot be found for one of these keys, this accessor
    /// returns `nil`.
    var versionString: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ??
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
