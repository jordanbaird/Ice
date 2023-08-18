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

    /// A rounded rectangle with zero or more of its rounded corners
    /// replaced with sharp right angles.
    private struct ClipShape: Shape {
        /// The edges whose rounded corners should be replaced with
        /// sharp right angles.
        let flattenedEdges: Edge.Set

        func path(in rect: CGRect) -> Path {
            Path { path in
                if flattenedEdges == .all {
                    // fast path (pun not intended)
                    path.addRect(rect)
                    return
                }
                let cornerRadius: CGFloat = 5
                path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
                if flattenedEdges.contains(.leading) {
                    flatten(edge: .minXEdge, of: &path, atDistance: cornerRadius)
                }
                if flattenedEdges.contains(.trailing) {
                    flatten(edge: .maxXEdge, of: &path, atDistance: cornerRadius)
                }
                if flattenedEdges.contains(.top) {
                    flatten(edge: .maxYEdge, of: &path, atDistance: cornerRadius)
                }
                if flattenedEdges.contains(.bottom) {
                    flatten(edge: .minYEdge, of: &path, atDistance: cornerRadius)
                }
            }
        }

        func flatten(edge: CGRectEdge, of path: inout Path, atDistance distance: CGFloat) {
            let slice = path.boundingRect.divided(atDistance: distance, from: edge).slice
            path = Path(path.cgPath.union(Path(slice).cgPath))
        }
    }

    @State private var frame = CGRect.zero
    @State private var isPressed = false

    /// The edges whose rounded corners should be replaced with
    /// sharp right angles.
    let flattenedEdges: Edge.Set

    /// Creates a settings button style with the rounded corners
    /// of the given edges being replaced with sharp right angles.
    init(flattenedEdges: Edge.Set = []) {
        self.flattenedEdges = flattenedEdges
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.medium)
                }
            }
            .padding(EdgeInsets(top: 2.5, leading: 10, bottom: 3.5, trailing: 10))
            .background {
                VisualEffectView(
                    material: .contentBackground,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .opacity(0.5)
                .background(isPressed ? .secondary : .tertiary)
                .clipShape(ClipShape(flattenedEdges: flattenedEdges))
            }
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
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        frame = proxy.frame(in: .local)
                    }
                }
            }
    }
}
