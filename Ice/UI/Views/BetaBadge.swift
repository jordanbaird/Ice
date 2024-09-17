//
//  BetaBadge.swift
//  Ice
//

import SwiftUI

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .background {
                Capsule(style: .circular)
                    .stroke()
            }
            .foregroundStyle(.green)
    }
}
