//
//  EnvironmentReader.swift
//  Ice
//

import SwiftUI

/// A container view that reads values from the environment and
/// injects them into a content-producing closure.
struct EnvironmentReader<Value, Content: View>: View {
    @Environment private var value: Value

    private let content: (Value) -> Content

    /// Creates a view that reads an environment value from a key path
    /// and injects it into a closure to produce its content.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to a value in the current environment.
    ///   - content: A closure that produces a content view using the
    ///     environment value retrieved from `keyPath`.
    init(_ keyPath: KeyPath<EnvironmentValues, Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self._value = Environment(keyPath)
        self.content = content
    }

    /// Creates a view that reads the values in the current environment
    /// and injects them into a closure to produce its content.
    ///
    /// - Parameter content: A closure that produces a content view using
    ///   the values in the current environment.
    init(@ViewBuilder content: @escaping (Value) -> Content) where Value == EnvironmentValues {
        self.init(\.self, content: content)
    }

    var body: some View {
        content(value)
    }
}

// MARK: - Background and Overlay

extension View {
    /// Reads the specified environment value from the view, using it
    /// to produce a second view that is applied as a background to the
    /// original view.
    ///
    /// - Parameters:
    ///   - keyPath: The environment value to read.
    ///   - alignment: An optional alignment to use when positioning the
    ///     background view relative to the original view.
    ///   - transform: A function that produces the background view from
    ///     the environment value read from the original view.
    ///
    /// - Returns: A view that layers a second view behind the view.
    func backgroundEnvironmentValue<Value, Background: View>(
        _ keyPath: KeyPath<EnvironmentValues, Value>,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Value) -> Background
    ) -> some View {
        background(alignment: alignment) {
            EnvironmentReader(keyPath) { value in
                transform(value)
            }
        }
    }

    /// Reads the specified environment value from the view, using it
    /// to produce a second view that is applied as an overlay to the
    /// original view.
    ///
    /// - Parameters:
    ///   - keyPath: The environment value to read.
    ///   - alignment: An optional alignment to use when positioning the
    ///     overlay view relative to the original view.
    ///   - transform: A function that produces the overlay view from
    ///     the environment value read from the original view.
    ///
    /// - Returns: A view that layers a second view in front of the view.
    func overlayEnvironmentValue<Value, Overlay: View>(
        _ keyPath: KeyPath<EnvironmentValues, Value>,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Value) -> Overlay
    ) -> some View {
        overlay(alignment: alignment) {
            EnvironmentReader(keyPath) { value in
                transform(value)
            }
        }
    }
}
