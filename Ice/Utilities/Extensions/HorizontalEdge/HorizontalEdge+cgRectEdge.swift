//
//  HorizontalEdge+cgRectEdge.swift
//  Ice
//

import SwiftUI

extension HorizontalEdge {
    /// The CoreGraphics equivalent to this edge.
    var cgRectEdge: CGRectEdge {
        switch self {
        case .leading: .minXEdge
        case .trailing: .maxXEdge
        }
    }
}
