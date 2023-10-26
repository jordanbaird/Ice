//
//  CustomButtonStyle.swift
//  Ice
//

import SwiftUI

// MARK: - CustomButtonStyle

/// A custom button style to use in the app's interface.
struct CustomButtonStyle: PrimitiveButtonStyle {
    /// A custom view that prevents mouse down messages from
    /// passing through to the button's window.
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
        let shape: CustomButtonConfiguration.ButtonShape

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

    @Environment(\.customButtonConfiguration.bezelOpacity) private var bezelOpacity
    @Environment(\.customButtonConfiguration.isHighlighted) private var isHighlighted
    @Environment(\.customButtonConfiguration.labelForegroundColor) private var labelForegroundColor
    @Environment(\.customButtonConfiguration.shape) private var shape
    @Environment(\.controlSize) private var controlSize
    @State private var horizontalPadding: CGFloat = 7
    @State private var verticalPadding: CGFloat = 2
    @State private var isPressed = false
    @State private var frame = CGRect.zero

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelForegroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .baselineOffset(1)
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.regular)
                }
            }
            .background {
                Color.primary
                    .opacity(isHighlighted ? 0.2 : 0)
                    .blendMode(.overlay)
                    .background(isPressed ? .tertiary : .quaternary)
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
            .onAppear {
                switch controlSize {
                case .mini:
                    horizontalPadding = 2
                    verticalPadding = 0
                case .small:
                    horizontalPadding = 4
                    verticalPadding = 1
                case .regular:
                    horizontalPadding = 7
                    verticalPadding = 2
                case .large:
                    horizontalPadding = 8
                    verticalPadding = 6
                case .extraLarge:
                    horizontalPadding = 12
                    verticalPadding = 8
                @unknown default:
                    break
                }
            }
    }
}

extension PrimitiveButtonStyle where Self == CustomButtonStyle {
    /// A custom button style to use in the app's interface.
    static var custom: CustomButtonStyle {
        CustomButtonStyle()
    }
}

// MARK: - CustomButtonConfiguration

/// A configuration that determines the appearance and behavior
/// of a custom button.
struct CustomButtonConfiguration {
    /// A configuration that determines the shape of a custom button.
    struct ButtonShape {
        /// The flattened edges of the buttons that use this configuration.
        var flattenedEdges: Edge.Set = []

        /// A configuration for a settings button with the shape of a
        /// leading segment in a segmented control.
        static let leadingSegment = ButtonShape(flattenedEdges: .trailing)

        /// A configuration for a settings button with the shape of a
        /// trailing segment in a segmented control.
        static let trailingSegment = ButtonShape(flattenedEdges: .leading)
    }

    /// The opacity of the button's bezel.
    var bezelOpacity: CGFloat = 1

    /// A Boolean value that indicates whether the button is drawn
    /// with a highlighted style.
    ///
    /// This value is distinct from the button's pressed state;
    /// that is, the button can be pressed, highlighted, or both.
    var isHighlighted = false

    /// The foreground color of the button's label.
    var labelForegroundColor = Color.primary

    /// The shape of the button.
    var shape = ButtonShape()
}

private extension EnvironmentValues {
    struct CustomButtonConfigurationKey: EnvironmentKey {
        static let defaultValue = CustomButtonConfiguration()
    }

    var customButtonConfiguration: CustomButtonConfiguration {
        get { self[CustomButtonConfigurationKey.self] }
        set { self[CustomButtonConfigurationKey.self] = newValue }
    }
}

extension View {
    /// Configures the properties of buttons in this view using
    /// the given closure.
    ///
    /// - Parameter configure: A closure that updates the current
    ///   environment's custom button configuration with new values.
    func customButtonConfiguration(
        configure: @escaping (inout CustomButtonConfiguration) -> Void
    ) -> some View {
        transformEnvironment(\.customButtonConfiguration, transform: configure)
    }
}
