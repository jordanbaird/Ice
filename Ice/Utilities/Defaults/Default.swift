//
//  Default.swift
//  Ice
//

import Foundation

/// A property wrapper type that reads and writes a value stored
/// in a `UserDefaults` suite.
@propertyWrapper
struct Default<Value> {
    /// The key used to access the value.
    let key: String

    /// The `UserDefaults` suite where the value is stored.
    let suite: UserDefaults

    /// A closure that computes a default value to use in case a
    /// value isn't stored for the wrapper's key.
    let computeDefault: () -> Value

    /// The stored value.
    var wrappedValue: Value {
        get { suite.object(forKey: key) as? Value ?? computeDefault() }
        set { suite.set(newValue, forKey: key) }
    }

    /// Creates a wrapper that reads and writes a value using the given
    /// key, `UserDefaults` suite, and default value.
    init(
        key: String,
        suite: UserDefaults = .standard,
        default computeDefault: @escaping @autoclosure () -> Value
    ) {
        self.key = key
        self.suite = suite
        self.computeDefault = computeDefault
    }

    /// Creates a wrapper that reads and writes an optional value using
    /// the given key and `UserDefaults` suite.
    init<T>(key: String, suite: UserDefaults = .standard) where Value == T? {
        self.init(key: key, suite: suite, default: nil)
    }
}
