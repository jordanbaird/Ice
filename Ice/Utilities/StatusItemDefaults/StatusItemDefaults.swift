//
//  StatusItemDefaults.swift
//  Ice
//

import Foundation

/// Proxy getters and setters for a status item's user default values.
enum StatusItemDefaults {
    private static func stringKey<Value>(forKey key: StatusItemDefaultsKey<Value>, autosaveName: String) -> String {
        return "NSStatusItem \(key.rawValue) \(autosaveName)"
    }

    /// Accesses the value associated with the specified key and autosave name.
    static subscript<Value>(key: StatusItemDefaultsKey<Value>, autosaveName: String) -> Value? {
        get {
            let key = stringKey(forKey: key, autosaveName: autosaveName)
            return UserDefaults.standard.object(forKey: key) as? Value
        }
        set {
            let key = stringKey(forKey: key, autosaveName: autosaveName)
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    /// Migrates the given status item defaults key from an old autosave name to a new autosave name.
    static func migrate<Value>(key: StatusItemDefaultsKey<Value>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }
}
