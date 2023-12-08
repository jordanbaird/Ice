//
//  NSBezierPath+intersects.swift
//  Ice
//

import Cocoa

extension NSBezierPath {
    /// Returns a Boolean value that indicates whether this
    /// path and another path overlap.
    ///
    /// - Parameters:
    ///   - other: Another path.
    ///   - windingRule: The winding rule to determine whether
    ///     the paths overlap.
    func intersects(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> Bool {
        let fillRule: CGPathFillRule = switch windingRule {
        case .nonZero: .winding
        case .evenOdd: .evenOdd
        @unknown default:
            fatalError("Unknown winding rule \(windingRule)")
        }
        return cgPath.intersects(other.cgPath, using: fillRule)
    }
}
