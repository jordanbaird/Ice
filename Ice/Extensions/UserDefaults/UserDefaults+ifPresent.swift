//
//  UserDefaults+ifPresent.swift
//  Ice
//

import Foundation

extension UserDefaults {
    /// Reads the value for the given key, and, if it is
    /// present, assigns it to the given `inout` parameter.
    func ifPresent<Value>(key: String, assign value: inout Value) {
        if let found = object(forKey: key) as? Value {
            value = found
        }
    }

    /// Reads the value for the given key, and, if it is
    /// present, performs the given closure.
    func ifPresent<Value>(key: String, body: (Value) throws -> Void) rethrows {
        if let found = object(forKey: key) as? Value {
            try body(found)
        }
    }
}
