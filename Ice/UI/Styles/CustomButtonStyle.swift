//
//  CustomButtonStyle.swift
//  Ice
//

import SwiftUI

// MARK: - CustomButtonStyle

/// A custom button style to use in the app's interface.
struct CustomButtonStyle: PrimitiveButtonStyle {
    /// Custom view that prevents mouse down messages from passing through to
    /// the button's window.
    private struct MouseDownInterceptor: NSViewRepresentable {
        private class Represented: NSView {
            override var mouseDownCanMoveWindow: Bool { false }
        }

        func makeNSView(context _: Context) -> NSView { Represented() }
        func updateNSView(_: NSView, context _: Context) {}
    }

    /// Custom view that ensures that the button accepts the first mouse input.
    private struct FirstMouseOverlay: NSViewRepresentable {
        private class Represented: NSView {
            override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
        }

        func makeNSView(context _: Context) -> NSView { Represented() }
        func updateNSView(_: NSView, context _: Context) {}
    }

    @Environment(\.controlSize) private var controlSize
    @Environment(\.customButtonConfiguration) private var customButtonConfiguration
    @State private var frame = CGRect.zero
    @State private var isPressed = false
    @State private var padding = EdgeInsets()

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(customButtonConfiguration.labelForegroundColor)
            .font(customButtonConfiguration.font)
            .padding(padding + customButtonConfiguration.labelPadding)
            .offset(y: -0.5)
            .lineLimit(1)
            .background {
                customButtonConfiguration.highlightColor
                    .opacity(customButtonConfiguration.isHighlighted ? 1 : 0)
                    .background(isPressed ? .tertiary : .quaternary)
                    .background {
                        MouseDownInterceptor()
                    }
                    .clipShape(UnevenRoundedRectangle(cornerRadii: customButtonConfiguration.shape.cornerRadii))
                    .opacity(customButtonConfiguration.bezelOpacity)
            }
            .overlay {
                FirstMouseOverlay()
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
                    padding = EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3)
                case .small:
                    padding = EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
                case .regular:
                    padding = EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
                case .large:
                    padding = EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9)
                case .extraLarge:
                    padding = EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13)
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
        /// The corner radii of the shape.
        var cornerRadii = RectangleCornerRadii(leading: 5, trailing: 5)

        /// A configuration for a button with the shape of a leading
        /// segment in a segmented control.
        static let leadingSegment = ButtonShape(cornerRadii: RectangleCornerRadii(leading: 5))

        /// A configuration for a button with the shape of a trailing
        /// segment in a segmented control.
        static let trailingSegment = ButtonShape(cornerRadii: RectangleCornerRadii(trailing: 5))
    }

    /// The opacity of the button's bezel.
    var bezelOpacity: CGFloat = 1

    /// A Boolean value that indicates whether the button is drawn
    /// with a highlighted style.
    ///
    /// This value is distinct from the button's pressed state;
    /// that is, the button can be pressed, highlighted, or both.
    var isHighlighted = false

    /// The color of the button when it is highlighted.
    var highlightColor = Color.primary.opacity(0.2)

    /// The foreground color of the button's label.
    var labelForegroundColor = Color.primary

    /// The font of the button's label.
    var font = Font.body.weight(.medium)

    /// Extra padding for the button's label.
    var labelPadding = EdgeInsets()

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
        configure: @escaping (_ configuration: inout CustomButtonConfiguration) -> Void
    ) -> some View {
        transformEnvironment(\.customButtonConfiguration, transform: configure)
    }
}
