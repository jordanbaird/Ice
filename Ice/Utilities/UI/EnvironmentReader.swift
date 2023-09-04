//
//  EnvironmentReader.swift
//  Ice
//

import SwiftUI

/// A container view that reads values from the environment and injects
/// them into a content-producing closure.
struct EnvironmentReader<Value, Content: View>: View {
    @Environment private var value: Value
    private let content: (Value) -> Content

    var body: some View {
        content(value)
    }

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
    init(@ViewBuilder content: @escaping (_ environment: Value) -> Content) where Value == EnvironmentValues {
        self.init(\.self, content: content)
    }
}

extension View {
    func backgroundEnvironmentValue<Value, Background: View>(
        _ keyPath: KeyPath<EnvironmentValues, Value>,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Value) -> Background
    ) -> some View {
        background(
            EnvironmentReader(keyPath) { value in
                transform(value)
            },
            alignment: alignment
        )
    }

    func overlayEnvironmentValue<Value, Overlay: View>(
        _ keyPath: KeyPath<EnvironmentValues, Value>,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Value) -> Overlay
    ) -> some View {
        overlay(
            EnvironmentReader(keyPath) { value in
                transform(value)
            },
            alignment: alignment
        )
    }
}
