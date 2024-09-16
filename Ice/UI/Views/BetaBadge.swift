//
//  BetaBadge.swift
//  Ice
//

import SwiftUI

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .foregroundStyle(.green)
            .font(.caption)
            .padding(.horizontal, 6)
            .background {
                Capsule(style: .circular)
                    .fill(.quinary)
            }
    }
}
