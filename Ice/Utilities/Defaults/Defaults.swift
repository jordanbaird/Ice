//
//  Defaults.swift
//  Ice
//

import SwiftUI

/// A namespace for values stored in `UserDefaults`.
enum Defaults {
    /// Accesses the value stored for the given key.
    static subscript<Value>(key: Key<Value>) -> Value {
        get { key.suite.object(forKey: key.stringValue) as? Value ?? key.defaultValue }
        set { key.suite.set(newValue, forKey: key.stringValue) }
    }
}

extension Defaults.Keys {
    static let enableAlwaysHidden = Key("EnableAlwaysHidden", default: true)
    static let serializedControlItems = Key("ControlItems", default: [String: Any]())
}

extension AppStorage {
    init(key: Defaults.Key<Value>) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Double {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Data {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == URL {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }
}

extension AppStorage where Value: RawRepresentable {
    init(key: Defaults.Key<Value>) where Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value.RawValue == Int {
        self.init(wrappedValue: key.defaultValue, key.stringValue, store: key.suite)
    }
}

extension AppStorage where Value: ExpressibleByNilLiteral {
    init(key: Defaults.Key<Value>) where Value == String? {
        self.init(key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Int? {
        self.init(key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Double? {
        self.init(key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Bool? {
        self.init(key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == Data? {
        self.init(key.stringValue, store: key.suite)
    }

    init(key: Defaults.Key<Value>) where Value == URL? {
        self.init(key.stringValue, store: key.suite)
    }

    init<R: RawRepresentable>(key: Defaults.Key<Value>) where Value == R?, R.RawValue == String {
        self.init(key.stringValue, store: key.suite)
    }

    init<R: RawRepresentable>(key: Defaults.Key<Value>) where Value == R?, R.RawValue == Int {
        self.init(key.stringValue, store: key.suite)
    }
}
