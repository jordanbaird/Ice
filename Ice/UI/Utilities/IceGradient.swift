//
//  IceGradient.swift
//  Ice
//

import SwiftUI

// MARK: - IceGradient

/// A custom gradient.
struct IceGradient: Codable, Hashable {
    /// The color stops in the gradient.
    var stops: [ColorStop]

    /// Creates a gradient with the given array of color stops.
    ///
    /// - Parameter stops: An array of color stops.
    init(stops: [ColorStop] = []) {
        self.stops = stops
    }

    /// Returns a copy of the gradient with the given alpha value.
    func withAlpha(_ alpha: CGFloat) -> IceGradient {
        let newStops = stops.map { $0.withAlpha(alpha) }
        return IceGradient(stops: newStops)
    }

    /// Returns a Cocoa representation of the gradient, converted to the
    /// given color space.
    ///
    /// - Parameter colorSpace: The color space to convert the gradient to.
    func nsGradient(using colorSpace: NSColorSpace) -> NSGradient? {
        guard !stops.isEmpty else {
            return nil
        }

        var colors = [NSColor]()
        var locations = [CGFloat]()

        for stop in stops {
            guard let color = NSColor(cgColor: stop.color) else {
                continue
            }
            colors.append(color)
            locations.append(stop.location)
        }

        return NSGradient(colors: colors, atLocations: &locations, colorSpace: colorSpace)
    }

    /// Returns a SwiftUI representation of the gradient, converted to the
    /// given color space.
    ///
    /// - Parameter colorSpace: The color space to convert the gradient to.
    func swiftUIView(using colorSpace: Color.RGBColorSpace) -> some View {
        GeometryReader { geometry in
            if stops.isEmpty {
                Color.clear
            } else if let space = colorSpace.nsColorSpace {
                Image(nsImage: NSImage(size: geometry.size, flipped: false) { bounds in
                    guard let gradient = nsGradient(using: space) else {
                        return false
                    }
                    gradient.draw(in: bounds, angle: 0)
                    return true
                })
            }
        }
    }

    /// Returns the color at the given location in the gradient.
    ///
    /// This method does not simply return the color of the nearest color
    /// stop. Instead, it computes the actual rendered color at `location`.
    ///
    /// - Parameters:
    ///   - location: A value between 0 and 1 representing the location
    ///     of the color to return.
    ///   - colorSpace: The color space used to process the colors in the
    ///     gradient. The returned color also uses this color space.
    func color(at location: CGFloat, using colorSpace: CGColorSpace) -> CGColor? {
        guard
            let space = NSColorSpace(cgColorSpace: colorSpace),
            let gradient = nsGradient(using: space)
        else {
            return nil
        }
        return gradient.interpolatedColor(atLocation: location).cgColor
    }

    /// Returns the color at the given location in the gradient.
    ///
    /// This method does not simply return the color of the nearest color
    /// stop. Instead, it computes the actual rendered color at `location`.
    ///
    /// This method uses the extended Display P3 color space to process the
    /// colors in the gradient. The same color space is also used to create
    /// the returned color. Converting the color to a different color space
    /// may produce unexpected results. Prefer ``color(at:using:)`` if you
    /// need the color returned in a different color space.
    ///
    /// - Parameter location: A value between 0 and 1 representing the
    ///   location of the color to return.
    func color(at location: CGFloat) -> CGColor? {
        guard let space = Color.RGBColorSpace.displayP3.cgColorSpace else {
            return nil
        }
        return color(at: location, using: space)
    }

    /// Returns the average color of the gradient.
    ///
    /// - Parameters:
    ///   - colorSpace: The color space used to process the colors in the
    ///     gradient. The returned color also uses this color space. Must
    ///     be an RGB color space, or this parameter is ignored. Pass `nil`
    ///     to let the method decide the color space.
    ///   - option: Options for computing the color.
    func averageColor(using colorSpace: CGColorSpace? = nil, option: CGImage.ColorAverageOption = []) -> CGColor? {
        guard !stops.isEmpty else {
            return nil
        }

        let colorSpace: CGColorSpace = {
            if let colorSpace, colorSpace.model == .rgb {
                return colorSpace
            }
            if let colorSpace = Color.RGBColorSpace.displayP3.cgColorSpace {
                return colorSpace
            }
            return CGColorSpaceCreateDeviceRGB()
        }()

        let colors = stride(from: 0, through: 1, by: 1 / CGFloat(stops.count)).compactMap { location in
            color(at: location, using: colorSpace)
        }

        var totals: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) = (0, 0, 0, 0)
        var count: CGFloat = 0

        for color in colors {
            guard let components = color.components else {
                continue
            }
            totals.red += components[0]
            totals.green += components[1]
            totals.blue += components[2]
            totals.alpha += components[3]
            count += 1
        }

        var components: [CGFloat] = [
            totals.red / count,
            totals.green / count,
            totals.blue / count,
            option.contains(.ignoreAlpha) ? 1 : (totals.alpha / count),
        ]

        return CGColor(colorSpace: colorSpace, components: &components)
    }
}

// MARK: IceGradient Static Members
extension IceGradient {
    /// The default menu bar tint gradient.
    static let defaultMenuBarTint = IceGradient(stops: [
        ColorStop.white(location: 0),
        ColorStop.black(location: 1),
    ])
}

// MARK: - IceGradient.ColorStop

extension IceGradient {
    /// A color stop in a gradient.
    struct ColorStop: Hashable {
        /// The stop's color.
        var color: CGColor
        /// The stop's relative location in a gradient.
        var location: CGFloat

        /// Returns a stop with the given color and location.
        static func stop(_ color: CGColor, location: CGFloat) -> ColorStop {
            ColorStop(color: color, location: location)
        }

        /// Returns a stop with a white color suitable for use in a gradient.
        static func white(location: CGFloat) -> ColorStop {
            let srgbWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            return ColorStop(color: srgbWhite, location: location)
        }

        /// Returns a stop with a black color suitable for use in a gradient.
        static func black(location: CGFloat) -> ColorStop {
            let srgbBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            return ColorStop(color: srgbBlack, location: location)
        }

        /// Returns a copy of the stop with the given alpha value.
        func withAlpha(_ alpha: CGFloat) -> ColorStop {
            let newColor = color.copy(alpha: alpha) ?? color
            return ColorStop(color: newColor, location: location)
        }

        /// Returns a copy of the stop with the given location.
        func withLocation(_ location: CGFloat) -> ColorStop {
            ColorStop(color: color, location: location)
        }
    }
}

// MARK: IceGradient.ColorStop: Codable
extension IceGradient.ColorStop: Codable {
    private enum CodingKeys: CodingKey {
        case color
        case location
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decode(IceColor.self, forKey: .color).cgColor
        self.location = try container.decode(CGFloat.self, forKey: .location)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(IceColor(cgColor: color), forKey: .color)
        try container.encode(location, forKey: .location)
    }
}

// MARK: - Color Space Helpers

private extension Color.RGBColorSpace {
    var cgColorSpaceName: CFString? {
        switch self {
        case .sRGB: CGColorSpace.extendedSRGB
        case .sRGBLinear: CGColorSpace.extendedLinearSRGB
        case .displayP3: CGColorSpace.extendedDisplayP3
        @unknown default: nil
        }
    }

    var cgColorSpace: CGColorSpace? {
        guard let name = cgColorSpaceName else {
            return nil
        }
        return CGColorSpace(name: name)
    }

    var nsColorSpace: NSColorSpace? {
        guard let space = cgColorSpace else {
            return nil
        }
        return NSColorSpace(cgColorSpace: space)
    }
}
