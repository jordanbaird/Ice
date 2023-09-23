//
//  SettingsButtonConfiguration.swift
//  Ice
//

import SwiftUI

/// A configuration that determines the appearance and behavior of
/// a settings button.
struct SettingsButtonConfiguration {
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

extension SettingsButtonConfiguration {
    /// A configuration that determines the shape of a settings button.
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
    private struct SettingsButtonConfigurationKey: EnvironmentKey {
        static let defaultValue = SettingsButtonConfiguration()
    }

    var settingsButtonConfiguration: SettingsButtonConfiguration {
        get { self[SettingsButtonConfigurationKey.self] }
        set { self[SettingsButtonConfigurationKey.self] = newValue }
    }
}

extension View {
    /// Configures the properties of settings buttons in this view
    /// using the given closure.
    ///
    /// - Parameter configure: A closure that updates the current
    ///   environment's settings button configuration with new values.
    func settingsButtonConfiguration(
        configure: @escaping (inout SettingsButtonConfiguration) -> Void
    ) -> some View {
        transformEnvironment(\.settingsButtonConfiguration, transform: configure)
    }
}
