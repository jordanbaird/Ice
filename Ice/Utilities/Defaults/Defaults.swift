//
//  Defaults.swift
//  Ice
//

/// A namespace for values stored in `UserDefaults`.
enum Defaults {
    @Default(key: "EnableAlwaysHidden", default: true)
    static var enableAlwaysHidden: Bool

    @Default(key: "ControlItems", default: [:])
    static var serializedControlItems: [String: Any]
}
