//
//  OverlayView.swift
//  Ice
//

import SwiftUI

struct OverlayView<Content: View>: View {
    @Binding var isVisible: Bool

    private let content: Content

    init(isVisible: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isVisible = isVisible
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            overlay
                .frame(
                    maxWidth: proxy.size.width * 0.75,
                    maxHeight: proxy.size.height * 0.75
                )
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
        }
        .animation(.default, value: isVisible)
        .transition(.opacity)
    }

    @ViewBuilder
    private var overlay: some View {
        if isVisible {
            content
                .background(
                    VisualEffectView(
                        material: .toolTip,
                        blendingMode: .withinWindow,
                        state: .active,
                        isEmphasized: true
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                )
                .shadow(color: .black.opacity(0.25), radius: 1)
                .onHover { isInside in
                    if isInside {
                        isVisible = false
                    }
                }
        }
    }
}
