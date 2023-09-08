//
//  ErrorOverlay.swift
//  Ice
//

import SwiftUI

private struct ErrorPreferenceKey<E: Error & Equatable>: PreferenceKey {
    static var defaultValue: E? { nil }

    static func reduce(value: inout E?, nextValue: () -> E?) {
        value = value ?? nextValue()
    }
}

private struct ErrorOverlay<E: Error & Equatable, Content: View>: View {
    @State private var showOverlay = false
    @State private var error: E?
    private let content: Content

    init(type: E.Type, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        OverlayView(showOverlay: $showOverlay) {
            content
        } overlay: {
            Text(error?.localizedDescription ?? "")
                .font(.system(size: 18, weight: .light))
        }
        .onPreferenceChange(ErrorPreferenceKey<E>.self) {
            showOverlay = $0 != nil
            error = $0
        }
    }
}

extension View {
    /// Presents a descriptive overlay when errors of the given type
    /// occur.
    ///
    /// The overlay can be triggered by setting an error of the same
    /// type using the ``error(_:)`` modifier elsewhere in the view
    /// hierarchy.
    ///
    /// - Parameter type: The type of error to display a descriptive
    ///   overlay for.
    func overlayErrors<E: Error & Equatable>(_ type: E.Type) -> some View {
        ErrorOverlay(type: type) { self }
    }

    /// Sets an error to be displayed over the top of any view that has
    /// applied the ``overlayErrors(_:)`` modifier for the same error
    /// type as the provided error.
    ///
    /// - Parameter error: An error to display a descriptive overlay for.
    func error<E: Error & Equatable>(_ error: E?) -> some View {
        preference(key: ErrorPreferenceKey.self, value: error)
    }
}
