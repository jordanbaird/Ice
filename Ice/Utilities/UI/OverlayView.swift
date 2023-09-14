//
//  OverlayView.swift
//  Ice
//

import SwiftUI

struct OverlayView<Content: View, Overlay: View>: View {
    @Binding var showOverlay: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            content
            GeometryReader { proxy in
                overlay(in: proxy.frame(in: .local))
            }
            .animation(.default, value: showOverlay)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func overlay(in frame: CGRect) -> some View {
        if showOverlay {
            overlay
                .padding()
                .background {
                    VisualEffectView(
                        material: .toolTip,
                        blendingMode: .withinWindow,
                        state: .active,
                        isEmphasized: true
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlayEnvironmentValue(\.colorScheme) { colorScheme in
                        VisualEffectView(
                            material: .selection,
                            blendingMode: .withinWindow,
                            state: .active,
                            isEmphasized: true
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .inset(by: colorScheme == .dark ? 1 : 0)
                                .stroke(lineWidth: 0.5)
                        )
                    }
                }
                .shadow(
                    color: .black.opacity(0.5),
                    radius: 10
                )
                .frame(
                    maxWidth: frame.width * 0.75,
                    maxHeight: frame.height * 0.75
                )
                .position(
                    x: frame.width / 2,
                    y: frame.height / 2
                )
        }
    }
}
