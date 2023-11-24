//
//  ColorStop.swift
//  Ice
//

import CoreGraphics

/// A color stop in a gradient.
struct ColorStop: Hashable {
    /// The color of the stop.
    var color: CGColor
    /// The location of the stop relative to its gradient.
    var location: CGFloat
}

extension ColorStop: Codable {
    private enum CodingKeys: CodingKey {
        case color
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decode(CodableColor.self, forKey: .color).cgColor
        self.location = try container.decode(CGFloat.self, forKey: .location)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CodableColor(cgColor: color), forKey: .color)
        try container.encode(location, forKey: .location)
    }
}
