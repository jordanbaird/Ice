//
//  UserDefaults+assignIfPresent.swift
//  Ice
//

import Foundation

extension UserDefaults {
    /// Reads the value for the given key, and, if it is
    /// present, assigns it to the given `inout` parameter.
    func assignIfPresent<Value>(_ value: inout Value, forKey key: String) {
        if let found = object(forKey: key) as? Value {
            value = found
        }
    }
}
