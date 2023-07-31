//
//  DictionarySerialization.swift
//  Ice
//

import Foundation

/// A type that converts between codable objects and their serialized
/// dictionary representations.
enum DictionarySerialization { }

// MARK: Underlying Coders
extension DictionarySerialization {
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return encoder
    }()

    private static let decoder = PropertyListDecoder()
}

// MARK: Type Methods
extension DictionarySerialization {
    /// Creates and returns a dictionary from the specified encodable value.
    static func dictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let result = try PropertyListSerialization.propertyList(from: data, format: nil)
        if let dictionary = result as? [String: Any] {
            return dictionary
        }
        return ["": result]
    }

    /// Creates and returns a value of the specified decodable type from the
    /// serialized values contained within the given dictionary.
    static func value<T: Decodable>(ofType type: T.Type, from dictionary: [String: Any]) throws -> T {
        let propertyList: Any
        if Array(dictionary.keys) == [""] {
            propertyList = dictionary.values.first!
        } else {
            propertyList = dictionary
        }
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        return try decoder.decode(type, from: data)
    }
}
