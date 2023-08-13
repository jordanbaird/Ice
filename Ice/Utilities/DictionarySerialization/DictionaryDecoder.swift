//
//  DictionaryDecoder.swift
//  Ice
//

import Foundation

/// An object that decodes instances of data types from a dictionary.
class DictionaryDecoder {
    private let baseDecoder: PropertyListDecoder

    /// Contextual information to customize the decoding process.
    var userInfo: [CodingUserInfoKey: Any] {
        get { baseDecoder.userInfo }
        set { baseDecoder.userInfo = newValue }
    }

    /// Creates a new dictionary decoder.
    init() {
        let baseDecoder = PropertyListDecoder()
        self.baseDecoder = baseDecoder
    }

    /// Returns a value of the specified type by decoding the values stored
    /// in the given dictionary.
    func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let propertyList: Any
        if Array(dictionary.keys) == [""] {
            propertyList = dictionary.values.first!
        } else {
            propertyList = dictionary
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        return try baseDecoder.decode(type, from: data)
    }
}
