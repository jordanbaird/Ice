//
//  BetaBadge.swift
//  Ice
//

import SwiftUI

/// A view that displays a badge indicating a beta feature.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .background {
                Capsule(style: .circular)
                    .stroke()
            }
            .foregroundStyle(.green.opacity(0.7))
    }
}
