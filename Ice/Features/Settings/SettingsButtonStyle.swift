//
//  SettingsButtonStyle.swift
//  Ice
//

import SwiftUI

/// The button style to use in the "Settings" interface.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    /// Custom view to prevent mouse down events from being passed through
    /// to the button's window.
    private struct MouseDownInterceptor: NSViewRepresentable {
        class Represented: NSView {
            override var mouseDownCanMoveWindow: Bool { false }
        }

        func makeNSView(context: Context) -> Represented {
            Represented()
        }

        func updateNSView(_ nsView: Represented, context: Context) { }
    }

    @State private var frame = CGRect.zero
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .padding(EdgeInsets(top: 2.5, leading: 10, bottom: 3.5, trailing: 10))
            .background(
                VisualEffectView(
                    material: .contentBackground,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .opacity(0.5)
                .background(isPressed ? .secondary : .tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            )
            .overlay(MouseDownInterceptor())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        isPressed = frame.contains(value.location)
                    }
                    .onEnded { value in
                        isPressed = false
                        if frame.contains(value.location) {
                            configuration.trigger()
                        }
                    }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            frame = proxy.frame(in: .local)
                        }
                }
            )
    }
}
