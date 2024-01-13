//
//  NSBezierPath+union.swift
//  Ice
//

import Cocoa

extension NSBezierPath {
    /// Returns a new path filled with regions in either this
    /// path or the given path.
    ///
    /// - Parameters:
    ///   - other: A path to union with this path.
    ///   - windingRule: The winding rule used to join the paths.
    func union(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> NSBezierPath {
        let fillRule: CGPathFillRule = switch windingRule {
        case .nonZero: .winding
        case .evenOdd: .evenOdd
        @unknown default:
            fatalError("Unknown winding rule \(windingRule)")
        }
        return NSBezierPath(cgPath: cgPath.union(other.cgPath, using: fillRule))
    }
}
