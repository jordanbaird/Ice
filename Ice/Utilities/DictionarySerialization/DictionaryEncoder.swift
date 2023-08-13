//
//  DictionaryEncoder.swift
//  Ice
//

import Foundation

/// An object that encodes instances of data types to a dictionary.
class DictionaryEncoder {
    private let baseEncoder: PropertyListEncoder

    /// Contextual information to customize the encoding process.
    var userInfo: [CodingUserInfoKey: Any] {
        get { baseEncoder.userInfo }
        set { baseEncoder.userInfo = newValue }
    }

    /// Creates a new dictionary encoder.
    init() {
        let baseEncoder = PropertyListEncoder()
        baseEncoder.outputFormat = .xml
        self.baseEncoder = baseEncoder
    }

    /// Returns a dictionary that represents an encoded version of the
    /// given value.
    func encode<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try baseEncoder.encode(value)
        let result = try PropertyListSerialization.propertyList(from: data, format: nil)
        if let dictionary = result as? [String: Any] {
            return dictionary
        }
        return ["": result]
    }
}
