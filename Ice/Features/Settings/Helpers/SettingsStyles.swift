//
//  SettingsStyles.swift
//  Ice
//

import SwiftUI

// MARK: - SettingsButtonConfiguration

/// A configuration that determines the appearance and behavior of a
/// settings button.
struct SettingsButtonConfiguration {
    /// The shape of the buttons that use this configuration.
    var buttonShape: ButtonShape

    /// A Boolean value that indicates whether the button is drawn with
    /// a highlighted style.
    ///
    /// This value is distinct from the button's pressed state; that is,
    /// the button can be pressed, highlighted, or both.
    var isHighlighted: Bool

    /// Creates a configuration with the given parameters.
    ///
    /// - Parameters:
    ///   - buttonShape: The shape of the buttons that use this configuration.
    ///   - isHighlighted: A Boolean value that indicates whether the button
    ///     is drawn with a highlighted style.
    init(
        buttonShape: ButtonShape = ButtonShape(),
        isHighlighted: Bool = false
    ) {
        self.buttonShape = buttonShape
        self.isHighlighted = isHighlighted
    }
}

// MARK: ShapeConfiguration
extension SettingsButtonConfiguration {
    /// A configuration that determines the shape of a settings button.
    struct ButtonShape {
        /// The flattened edges of the buttons that use this configuration.
        let flattenedEdges: Edge.Set

        /// Creates a configuration with the given flattened edges.
        init(flattenedEdges: Edge.Set = []) {
            self.flattenedEdges = flattenedEdges
        }

        /// A configuration for a settings button with the shape of a
        /// leading segment in a segmented control.
        static let leadingSegment = ButtonShape(flattenedEdges: .trailing)

        /// A configuration for a settings button with the shape of a
        /// trailing segment in a segmented control.
        static let trailingSegment = ButtonShape(flattenedEdges: .leading)
    }
}

private extension EnvironmentValues {
    struct SettingsButtonConfigurationKey: EnvironmentKey {
        static let defaultValue = SettingsButtonConfiguration()
    }

    var settingsButtonConfiguration: SettingsButtonConfiguration {
        get { self[SettingsButtonConfigurationKey.self] }
        set { self[SettingsButtonConfigurationKey.self] = newValue }
    }
}

extension View {
    /// Sets the configuration for settings buttons in this view.
    ///
    /// - Parameter configuration: The configuration to set.
    func settingsButtonConfiguration(_ configuration: SettingsButtonConfiguration) -> some View {
        environment(\.settingsButtonConfiguration, configuration)
    }

    /// Sets the shape for settings buttons in this view.
    ///
    /// - Parameter buttonShape: The shape of the buttons that use this
    ///   configuration.
    func settingsButtonShape(_ buttonShape: SettingsButtonConfiguration.ButtonShape) -> some View {
        environment(\.settingsButtonConfiguration.buttonShape, buttonShape)
    }

    /// Sets the highlight state for settings buttons in this view.
    ///
    /// The `isHighlighted` value is distinct from the button's pressed
    /// state; that is, the button can be pressed, highlighted, or both.
    ///
    /// - Parameter isHighlighted: A Boolean value that indicates whether
    ///   the button is drawn with a highlighted style.
    func settingsButtonIsHighlighted(_ isHighlighted: Bool) -> some View {
        environment(\.settingsButtonConfiguration.isHighlighted, isHighlighted)
    }
}

// MARK: - SettingsButtonStyle

/// The button style to use in the "Settings" interface.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    /// Custom shape that draws a rounded rectangle with some of its
    /// sides flattened according to the given id.
    private struct ClipShape: Shape {
        let cornerRadius: CGFloat
        let buttonShape: SettingsButtonConfiguration.ButtonShape

        func path(in rect: CGRect) -> Path {
            if buttonShape.flattenedEdges == .all {
                // fast path (pun not intended)
                return Path(rect)
            }
            var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
            if buttonShape.flattenedEdges.isEmpty {
                // fast path MkII
                return path
            }
            for edge in Edge.allCases where buttonShape.flattenedEdges.contains(Edge.Set(edge)) {
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 2.5)
            .baselineOffset(1)
            .transformEnvironment(\.font) { font in
                if font == nil {
                    font = .body.weight(.medium)
                }
            }
            .backgroundEnvironmentValue(\.settingsButtonConfiguration) { configuration in
                VisualEffectView(
                    material: .contentBackground,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .opacity(0.5)
                .background(isPressed ? .secondary : .tertiary)
                .overlay(
                    Color.primary
                        .opacity(configuration.isHighlighted ? 0.2 : 0)
                        .blendMode(.overlay)
                )
                .clipShape(ClipShape(cornerRadius: 5, buttonShape: configuration.buttonShape))
            }
            .interceptMouseDown()
            .onContinuousPress { info in
                isPressed = info.frame.contains(info.location)
            } onEnded: { info in
                isPressed = false
                if info.frame.contains(info.location) {
                    configuration.trigger()
                }
            }
    }
}

// MARK: - SettingsToggleStyle

struct SettingsToggleStyle: ToggleStyle {
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .inset(by: 0.5)
                .stroke(lineWidth: 1)
                .foregroundStyle(.tertiary)
                .overlay(
                    Image(systemName: configuration.isMixed ? "minus" : "checkmark")
                        .resizable()
                        .opacity(configuration.isOn ? 1 : 0)
                        .aspectRatio(contentMode: .fit)
                        .fontWeight(.heavy)
                        .padding(3)
                )
                .backgroundEnvironmentValue(\.colorScheme) { colorScheme in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colorScheme == .dark ? AnyShapeStyle(.selection) : AnyShapeStyle(.quaternary))
                        .opacity(isPressed ? 1 : 0)
                }
                .frame(width: 14, height: 14)

            configuration.label
        }
        .contentShape(Rectangle())
        .interceptMouseDown()
        .onContinuousPress { info in
            isPressed = info.frame.contains(info.location)
        } onEnded: { info in
            isPressed = false
            if info.frame.contains(info.location) {
                configuration.isOn.toggle()
            }
        }
    }
}
