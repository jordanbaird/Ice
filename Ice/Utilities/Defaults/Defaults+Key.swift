//
//  Defaults+Key.swift
//  Ice
//

import Foundation

extension Defaults {
    class _AnyKey {
        typealias Key = Defaults.Key

        let stringValue: String
        let suite: UserDefaults

        fileprivate init(stringValue: String, suite: UserDefaults) {
            self.stringValue = stringValue
            self.suite = suite
        }

        /// Resets the value stored under the key back to its default.
        func reset() {
            suite.removeObject(forKey: stringValue)
        }
    }
}

extension Defaults {
    class Key<Value>: _AnyKey {
        private let computeDefault: () -> Value

        var defaultValue: Value { computeDefault() }

        init(_ stringValue: String, suite: UserDefaults = .standard, computeDefault: @escaping () -> Value) {
            self.computeDefault = computeDefault
            super.init(stringValue: stringValue, suite: suite)
        }

        convenience init(_ stringValue: String, suite: UserDefaults = .standard, default defaultValue: Value) {
            self.init(stringValue, suite: suite) { defaultValue }
            suite.register(defaults: [stringValue: defaultValue])
        }

        convenience init<T>(_ stringValue: String, suite: UserDefaults = .standard) where Value == T? {
            self.init(stringValue, suite: suite, default: nil)
        }
    }
}

extension Defaults {
    typealias Keys = _AnyKey
}
