//
//  Edge+cgRectEdge.swift
//  Ice
//

import SwiftUI

extension Edge {
    /// The CoreGraphics equivalent to this edge.
    var cgRectEdge: CGRectEdge {
        switch self {
        case .top:      return .maxYEdge
        case .leading:  return .minXEdge
        case .bottom:   return .minYEdge
        case .trailing: return .maxXEdge
        }
    }
}
