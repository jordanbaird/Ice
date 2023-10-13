//
//  IceButtonConfiguration.swift
//  Ice
//

import SwiftUI

/// A configuration that determines the appearance and behavior
/// of a button in Ice's interface.
struct IceButtonConfiguration {
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

extension IceButtonConfiguration {
    /// A configuration that determines the shape of a button in
    /// Ice's interface.
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
}

extension EnvironmentValues {
    private struct IceButtonConfigurationKey: EnvironmentKey {
        static let defaultValue = IceButtonConfiguration()
    }

    var iceButtonConfiguration: IceButtonConfiguration {
        get { self[IceButtonConfigurationKey.self] }
        set { self[IceButtonConfigurationKey.self] = newValue }
    }
}

extension View {
    /// Configures the properties of buttons in this view using
    /// the given closure.
    ///
    /// - Parameter configure: A closure that updates the current
    ///   environment's configuration with new values.
    func iceButtonConfiguration(
        configure: @escaping (inout IceButtonConfiguration) -> Void
    ) -> some View {
        transformEnvironment(\.iceButtonConfiguration, transform: configure)
    }
}
