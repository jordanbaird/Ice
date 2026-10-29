//
//  IceButtonStyle.swift
//  Ice
//

import SwiftUI

/// Borderless macOS 27-style button: small blue text on a faint pill.
/// No borders, smaller type, lighter feel — like the reference design.
struct IceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.blue.opacity(configuration.isPressed ? 0.24 : 0.12))
            }
    }
}
