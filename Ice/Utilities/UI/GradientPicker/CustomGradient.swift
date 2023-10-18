//
//  CustomGradient.swift
//  Ice
//

import SwiftUI

// MARK: - CustomGradient

/// A custom gradient for use with a ``GradientPicker``.
struct CustomGradient: View {
    /// The color stops in the gradient.
    var stops: [ColorStop]

    /// A Cocoa representation of this gradient.
    var nsGradient: NSGradient? {
        let colors = stops.compactMap { stop in
            NSColor(cgColor: stop.color)
        }
        var locations = stops.map { stop in
            stop.location
        }
        guard colors.count == locations.count else {
            return nil
        }
        return NSGradient(
            colors: colors,
            atLocations: &locations,
            colorSpace: .sRGB
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if stops.isEmpty {
                Color.clear
            } else {
                Image(
                    nsImage: NSImage(
                        size: geometry.size,
                        flipped: false
                    ) { bounds in
                        guard let nsGradient else {
                            return false
                        }
                        nsGradient.draw(in: bounds, angle: 0)
                        return true
                    }
                )
            }
        }
    }

    /// Creates a gradient with the given unsorted stops.
    ///
    /// - Parameter stops: An array of color stops to sort and
    ///   assign as the gradient's color stops.
    init(unsortedStops stops: [ColorStop]) {
        self.stops = stops.sorted { $0.location < $1.location }
    }

    init() {
        self.init(unsortedStops: [])
    }

    /// Returns the color at the given location in the gradient.
    ///
    /// - Parameter location: A value between 0 and 1 representing
    ///   the location of the color that should be returned.
    func color(at location: CGFloat) -> CGColor? {
        guard
            let nsColor = nsGradient?.interpolatedColor(atLocation: location),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return nsColor.cgColor.converted(
            to: colorSpace,
            intent: .defaultIntent,
            options: nil
        )
    }
}

// MARK: CustomGradient: Codable
extension CustomGradient: Codable { }

// MARK: CustomGradient: Hashable
extension CustomGradient: Hashable { }

// MARK: - ColorStop

/// A color stop in a gradient.
struct ColorStop: Hashable {
    /// The color of the stop.
    var color: CGColor
    /// The location of the stop relative to its gradient.
    var location: CGFloat
}

// MARK: ColorStop: Codable
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
