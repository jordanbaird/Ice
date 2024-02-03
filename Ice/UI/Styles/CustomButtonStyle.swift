//
//  CustomButtonStyle.swift
//  Ice
//

import SwiftUI

// MARK: - CustomButtonStyle

/// A custom button style to use in the app's interface.
struct CustomButtonStyle: PrimitiveButtonStyle {
    /// Custom view that prevents mouse down messages from
    /// passing through to the button's window.
    private struct MouseDownInterceptor: NSViewRepresentable {
        private class Represented: NSView {
            override var mouseDownCanMoveWindow: Bool { false }
        }

        func makeNSView(context: Context) -> NSView {
            return Represented()
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
                // fast path
                return Path(rect)
            }
            var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
            if shape.flattenedEdges.isEmpty {
                // fast path
                return path
            }
            for edge in Edge.allCases where shape.flattenedEdges.contains(Edge.Set(edge)) {
                let slice = path.boundingRect.divided(atDistance: cornerRadius, from: edge.cgRectEdge).slice
                path = path.union(Path(slice))
            }
            return path
        }
    }

    @Environment(\.controlSize) private var controlSize
    @Environment(\.customButtonConfiguration) private var customButtonConfiguration
    @State private var frame = CGRect.zero
    @State private var isPressed = false
    @State private var padding = EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(customButtonConfiguration.labelForegroundColor)
            .padding(padding)
            .baselineOffset(1)
            .lineLimit(1)
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.regular)
                }
            }
            .background {
                Color.primary
                    .opacity(customButtonConfiguration.isHighlighted ? 0.2 : 0)
                    .blendMode(.overlay)
                    .background(isPressed ? .tertiary : .quaternary)
                    .background { MouseDownInterceptor() }
                    .clipShape(ClipShape(cornerRadius: 5, shape: customButtonConfiguration.shape))
                    .opacity(customButtonConfiguration.bezelOpacity)
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
            .onAppear {
                switch controlSize {
                case .mini:
                    padding = EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
                case .small:
                    padding = EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4)
                case .regular:
                    padding = EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7)
                case .large:
                    padding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
                case .extraLarge:
                    padding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                @unknown default:
                    break
                }
            }
            .onFrameChange(update: $frame)
    }
}

// MARK: - PrimitiveButtonStyle where Self == CustomButtonStyle

extension PrimitiveButtonStyle where Self == CustomButtonStyle {
    /// A custom button style to use in the app's interface.
    static var custom: CustomButtonStyle {
        CustomButtonStyle()
    }
}

// MARK: - CustomButtonConfiguration

/// A configuration that determines the appearance and behavior
/// of buttons using the `custom` button style.
struct CustomButtonConfiguration {
    /// A configuration that determines the shape of the button.
    struct ButtonShape {
        /// The flattened edges of the button.
        var flattenedEdges: Edge.Set = []

        /// A configuration for a button with the shape of a leading
        /// segment in a segmented control.
        static let leadingSegment = ButtonShape(flattenedEdges: .trailing)

        /// A configuration for a button with the shape of a trailing
        /// segment in a segmented control.
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
    /// Configures the properties of buttons in this view that use
    /// the `custom` button style.
    ///
    /// - Parameter configure: A closure that updates the current
    ///   environment's custom button configuration with new values.
    func customButtonConfiguration(
        configure: @escaping (inout CustomButtonConfiguration) -> Void
    ) -> some View {
        transformEnvironment(\.customButtonConfiguration, transform: configure)
    }
}
