//
//  DictionaryRepresentable.swift
//  Ice
//

protocol DictionaryRepresentable: Codable {
    var dictionaryValue: [String: Any] { get throws }
    init(dictionaryValue: [String: Any]) throws
}

private let defaultEncoder = DictionaryEncoder()
private let defaultDecoder = DictionaryDecoder()

extension DictionaryRepresentable {
    var dictionaryValue: [String: Any] {
        get throws {
            try defaultEncoder.encode(self)
        }
    }

    init(dictionaryValue: [String: Any]) throws {
        self = try defaultDecoder.decode(Self.self, from: dictionaryValue)
    }
}
