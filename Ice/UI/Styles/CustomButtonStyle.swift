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
        func makeNSView(context: Context) -> NSView { Represented() }
        func updateNSView(_: NSView, context: Context) { }
    }

    /// Custom view that ensures that the button accepts the first mouse input.
    private struct FirstMouseOverlay: NSViewRepresentable {
        private class Represented: NSView {
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        }
        func makeNSView(context: Context) -> NSView { Represented() }
        func updateNSView(_: NSView, context: Context) { }
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
                Color.primary
                    .opacity(customButtonConfiguration.isHighlighted ? 0.2 : 0)
                    .blendMode(.overlay)
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

    /// The foreground color of the button's label.
    var labelForegroundColor = Color.primary

    /// The font of the button's label.
    var font = Font.body.weight(.regular)

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
