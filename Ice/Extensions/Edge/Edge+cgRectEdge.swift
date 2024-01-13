//
//  Edge+cgRectEdge.swift
//  Ice
//

import SwiftUI

extension Edge {
    /// The CoreGraphics equivalent to this edge.
    var cgRectEdge: CGRectEdge {
        switch self {
        case .top: .maxYEdge
        case .leading: .minXEdge
        case .bottom: .minYEdge
        case .trailing: .maxXEdge
        }
    }
}
