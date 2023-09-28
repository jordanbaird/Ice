//
//  SettingsButtonStyle.swift
//  Ice
//

import SwiftUI

/// The button style to use in the "Settings" interface.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    /// Custom view that prevents mouse down messages from passing
    /// through to the button's window.
    private struct MouseDownInterceptor: NSViewRepresentable {
        private class Represented: NSView {
            override var mouseDownCanMoveWindow: Bool { false }
        }

        func makeNSView(context: Context) -> NSView {
            Represented()
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    /// Custom shape that draws a rounded rectangle with some of 
    /// its sides flattened according to the given button shape.
    private struct ClipShape: Shape {
        let cornerRadius: CGFloat
        let shape: SettingsButtonConfiguration.ButtonShape

        func path(in rect: CGRect) -> Path {
            if shape.flattenedEdges == .all {
                // fast path (pun not intended)
                return Path(rect)
            }
            var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
            if shape.flattenedEdges.isEmpty {
                // fast path MkII
                return path
            }
            for edge in Edge.allCases where shape.flattenedEdges.contains(Edge.Set(edge)) {
                flatten(edge: edge, of: &path)
            }
            return path
        }

        func flatten(edge: Edge, of path: inout Path) {
            let (rect, distance, edge) = (path.boundingRect, cornerRadius, edge.cgRectEdge)
            let slice = rect.divided(atDistance: distance, from: edge).slice
            path = Path(path.cgPath.union(Path(slice).cgPath))
        }
    }

    @State private var isPressed = false
    @State private var frame = CGRect.zero

    @Environment(\.settingsButtonConfiguration.bezelOpacity)
    private var bezelOpacity
    @Environment(\.settingsButtonConfiguration.isHighlighted)
    private var isHighlighted
    @Environment(\.settingsButtonConfiguration.labelForegroundColor)
    private var labelForegroundColor
    @Environment(\.settingsButtonConfiguration.shape)
    private var shape

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelForegroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .baselineOffset(1)
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.regular)
                }
            }
            .background {
                VisualEffectView(
                    material: .contentBackground,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .opacity(0.5)
                .background(isPressed ? .secondary : .tertiary)
                .overlay {
                    Color.primary
                        .opacity(isHighlighted ? 0.2 : 0)
                        .blendMode(.overlay)
                }
                .background {
                    MouseDownInterceptor()
                }
                .clipShape(ClipShape(cornerRadius: 5, shape: shape))
                .opacity(bezelOpacity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
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
            .onFrameChange(update: $frame)
    }
}
