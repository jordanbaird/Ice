//
//  CustomGradient.swift
//  Ice
//

import SwiftUI

/// A custom gradient for use with a ``GradientPicker``.
struct CustomGradient: View {
    /// The color stops in the gradient.
    var stops: [ColorStop]

    /// The color stops in the gradient, sorted by location.
    var sortedStops: [ColorStop] {
        stops.sorted { lhs, rhs in
            lhs.location < rhs.location
        }
    }

    /// A Cocoa representation of this gradient.
    var nsGradient: NSGradient? {
        let sortedStops = sortedStops
        let colors = sortedStops.compactMap { stop in
            NSColor(cgColor: stop.color)
        }
        var locations = sortedStops.map { stop in
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

    /// Returns a copy of the gradient with the given alpha value.
    func withAlphaComponent(_ alpha: CGFloat) -> CustomGradient {
        var copy = self
        copy.stops = copy.stops.map { stop in
            stop.withAlphaComponent(alpha) ?? stop
        }
        return copy
    }
}

extension CustomGradient {
    /// The default menu bar tint gradient.
    static let defaultMenuBarTint = CustomGradient(
        unsortedStops: [
            ColorStop(
                color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                location: 0
            ),
            ColorStop(
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                location: 1
            ),
        ]
    )
}

extension CustomGradient: Codable { }

extension CustomGradient: Hashable { }
